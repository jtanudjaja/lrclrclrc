import AppKit
import UniformTypeIdentifiers

struct NowPlaying {
    enum State { case ok, stopped, notRunning, permissionDenied }
    var state: State = .notRunning
    var title = ""
    var artist = ""
    var album = ""
    var duration: Double = 0
    var position: Double = 0
    var isPlaying = false
    var trackId = ""
}

/// A player lrclrclrc can read. Which ones are *enabled* is a Preferences
/// question; which enabled one the lyrics follow right now is a menu question.
enum PlayerSourceKind: String, CaseIterable {
    case appleMusic
    case spotify

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    /// Bundle ids to look for, in preference order.
    var bundleIDs: [String] {
        switch self {
        case .appleMusic: return ["com.apple.Music", "com.apple.iTunes"]
        case .spotify: return ["com.spotify.client"]
        }
    }

    /// The stable track-id key in the app's AppleScript dictionary.
    var idProperty: String {
        switch self {
        case .appleMusic: return "persistent ID"
        case .spotify: return "id"
        }
    }

    /// Multiplier turning the app's duration unit into seconds.
    var durationScale: Double {
        switch self {
        case .appleMusic: return 1
        case .spotify: return 0.001
        }
    }

    /// The distributed notification the app posts when playback changes.
    var changeNotification: String {
        switch self {
        case .appleMusic: return "com.apple.Music.playerInfo"
        case .spotify: return "com.spotify.client.PlaybackStateChanged"
        }
    }
}

/// One source's row in Preferences: a checkbox, plus whether we managed to
/// find the app behind it.
struct SourceState: Identifiable, Equatable {
    let kind: PlayerSourceKind
    let isInstalled: Bool
    let isEnabled: Bool
    var id: PlayerSourceKind { kind }
}

/// A controllable now-playing source.
protocol PlayerSource {
    func poll() -> NowPlaying
    func playPause()
    func nextTrack()
    func previousTrack()
    func seek(to seconds: Double)
}

// MARK: - Which players exist

/// Which players are installed, and which of them are enabled.
///
/// Installation is resolved through LaunchServices, never by asking
/// AppleScript. `tell application "Spotify"` on a Mac without Spotify makes
/// macOS pop its own "Where is Spotify?" file picker, and that fires when the
/// script is *compiled* — before any not-running guard inside the script gets
/// a chance to run. So nothing here hands a script to a player we haven't
/// located first.
///
/// Only the user's opt-*outs* are persisted. Anything installed is enabled by
/// default, which means a player added later is picked up on its own instead of
/// waiting behind a setting nobody knew to look for.
final class SourceRegistry {
    struct Located {
        let bundleID: String
        let url: URL
    }

    private(set) var located: [PlayerSourceKind: Located] = [:]

    init() { refresh() }

    /// Re-resolve every player. These are cheap LaunchServices lookups, so it's
    /// fine to run on launch and again whenever the user changes a source.
    func refresh() {
        var found: [PlayerSourceKind: Located] = [:]
        for kind in PlayerSourceKind.allCases {
            if let hit = locate(kind) { found[kind] = hit }
        }
        located = found
    }

    private func locate(_ kind: PlayerSourceKind) -> Located? {
        for id in kind.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return Located(bundleID: id, url: url)
            }
        }
        // A copy the user pointed us at by hand — installed somewhere
        // LaunchServices doesn't index, or under a bundle id we don't know.
        guard let path = Settings.sourceAppPath(for: kind),
              FileManager.default.fileExists(atPath: path),
              let id = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
        else { return nil }
        return Located(bundleID: id, url: URL(fileURLWithPath: path))
    }

    func isInstalled(_ kind: PlayerSourceKind) -> Bool { located[kind] != nil }

    func isEnabled(_ kind: PlayerSourceKind) -> Bool {
        isInstalled(kind) && !Settings.disabledSources.contains(kind.rawValue)
    }

    /// Installed and switched on — the sources lrclrclrc is allowed to read, and
    /// the only ones the "Follow" menu offers.
    var enabled: [PlayerSourceKind] { PlayerSourceKind.allCases.filter(isEnabled) }

    var states: [SourceState] {
        PlayerSourceKind.allCases.map {
            SourceState(kind: $0, isInstalled: isInstalled($0), isEnabled: isEnabled($0))
        }
    }

    /// Switch a source on or off. Switching one *on* that we couldn't find
    /// fails — the caller then asks the user where it is and comes back through
    /// `adopt`.
    func setEnabled(_ on: Bool, for kind: PlayerSourceKind) -> Bool {
        var off = Settings.disabledSources
        if on {
            guard isInstalled(kind) else { return false }
            off.remove(kind.rawValue)
        } else {
            off.insert(kind.rawValue)
        }
        Settings.disabledSources = off
        return true
    }

    /// Take the app the user picked as this source. Any real app bundle is
    /// accepted — a renamed or forked build is the whole reason they're here —
    /// and a wrong pick just fails to report a track, which is recoverable.
    func adopt(_ url: URL, as kind: PlayerSourceKind) -> Bool {
        guard let id = Bundle(url: url)?.bundleIdentifier else { return false }
        Settings.setSourceAppPath(url.path, for: kind)
        located[kind] = Located(bundleID: id, url: url)
        return setEnabled(true, for: kind)
    }

    /// Back to "enable everything installed, nothing hand-located, follow
    /// whichever is playing".
    func reset() {
        Settings.disabledSources = []
        Settings.selectedSource = nil
        for kind in PlayerSourceKind.allCases { Settings.setSourceAppPath(nil, for: kind) }
        refresh()
    }

    /// The one file picker in the app: shown only when the user switches on a
    /// player we couldn't find. It replaces the "Where is Spotify?" panel macOS
    /// used to throw at everyone who simply didn't have Spotify.
    static func askForApp(_ kind: PlayerSourceKind) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Locate \(kind.displayName)"
        panel.message = "lrclrclrc couldn't find \(kind.displayName) on this Mac. Choose it to enable it anyway."
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        // The app usually runs as an accessory, so the panel would otherwise
        // open behind whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Reading a player

/// Reads/controls a scriptable player (Apple Music, Spotify) via AppleScript.
/// Fields are joined with the ASCII unit separator (0x1F) so metadata with
/// commas/quotes survives intact.
///
/// The player is addressed by bundle id rather than by name: `application id`
/// resolves through LaunchServices and can't be satisfied by the user pointing
/// at some unrelated app in a dialog. The `is running` guard is outside the
/// `tell` block on purpose — sending any command to a quit app would launch it.
///
/// Thread-safety: NSAppleScript is not thread-safe, so *every* execution —
/// polls and playback commands alike — is confined to the one serial `queue`.
/// `poll()` must already be called on it; commands dispatch themselves onto it
/// (fire-and-forget), so a button press can never race a poll mid-execution.
final class AppleScriptPlayer: PlayerSource {
    private static let sep = "\u{1F}"
    private let bundleID: String
    private let durationScale: Double
    private let source: String
    private let queue: DispatchQueue
    // Created lazily on first poll; only ever touched on `queue`.
    private var script: NSAppleScript?

    init(kind: PlayerSourceKind, bundleID: String, queue: DispatchQueue) {
        self.bundleID = bundleID
        self.durationScale = kind.durationScale
        self.queue = queue
        self.source = """
        set d to (ASCII character 31)
        if not (application id "\(bundleID)" is running) then return "not-running"
        tell application id "\(bundleID)"
          set s to (player state as string)
          if s is not "playing" and s is not "paused" then return "stopped"
          try
            set t to current track
            set nm to name of t
            set ar to artist of t
            set al to album of t
            set dur to duration of t
            set pos to player position
            set pid to (\(kind.idProperty) of t)
            return "ok" & d & nm & d & ar & d & al & d & (dur as string) & d & (pos as string) & d & s & d & (pid as string)
          on error
            return "stopped"
          end try
        end tell
        """
    }

    func poll() -> NowPlaying {
        // Permission-free, dialog-free, and instant — and while the player is
        // closed it means AppleScript never runs at all.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            return NowPlaying(state: .notRunning)
        }
        if script == nil { script = NSAppleScript(source: source) }
        guard let script else { return NowPlaying(state: .notRunning) }
        var err: NSDictionary?
        let desc = script.executeAndReturnError(&err)
        if let err {
            // -1743 = user hasn't granted Automation permission.
            let code = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
            return NowPlaying(state: code == -1743 ? .permissionDenied : .notRunning)
        }

        let raw = desc.stringValue ?? ""
        if raw == "not-running" { return NowPlaying(state: .notRunning) }
        if !raw.hasPrefix("ok") { return NowPlaying(state: .stopped) }

        let parts = raw.components(separatedBy: AppleScriptPlayer.sep)
        guard parts.count >= 8 else { return NowPlaying(state: .stopped) }

        var np = NowPlaying(state: .ok)
        np.title = parts[1]
        np.artist = parts[2]
        np.album = parts[3]
        np.duration = (Double(parts[4]) ?? 0) * durationScale
        np.position = Double(parts[5]) ?? 0
        np.isPlaying = parts[6] == "playing"
        np.trackId = parts[7].isEmpty ? "\(parts[2])::\(parts[1])" : parts[7]
        return np
    }

    // MARK: - Playback commands (dispatched onto the script queue)

    func playPause() { run("playpause") }
    func nextTrack() { run("next track") }
    func previousTrack() { run("previous track") }
    func seek(to seconds: Double) { run("set player position to \(seconds)") }

    private func run(_ command: String) {
        let src = "tell application id \"\(bundleID)\" to \(command)"
        queue.async {
            guard let script = NSAppleScript(source: src) else { return }
            var err: NSDictionary?
            script.executeAndReturnError(&err)
        }
    }
}
