import Foundation

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

/// Which player the lyrics follow.
enum PlayerSourceKind: String {
    case auto
    case appleMusic
    case spotify
}

/// A controllable now-playing source.
protocol PlayerSource {
    func poll() -> NowPlaying
    func playPause()
    func nextTrack()
    func previousTrack()
    func seek(to seconds: Double)
}

/// Reads/controls a scriptable player (Apple Music, Spotify) via AppleScript.
/// Fields are joined with the ASCII unit separator (0x1F) so metadata with
/// commas/quotes survives intact. `durationScale` converts the app's duration
/// unit to seconds (Spotify reports milliseconds); `idProperty` is the track's
/// stable id key ("persistent ID" for Music, "id" for Spotify).
///
/// Thread-safety: NSAppleScript is not thread-safe, so *every* execution —
/// polls and playback commands alike — is confined to the one serial `queue`.
/// `poll()` must already be called on it; commands dispatch themselves onto it
/// (fire-and-forget), so a button press can never race a poll mid-execution.
final class AppleScriptPlayer: PlayerSource {
    private static let sep = "\u{1F}"
    private let appName: String
    private let durationScale: Double
    private let source: String
    private let queue: DispatchQueue
    // Created lazily on first poll; only ever touched on `queue`.
    private var script: NSAppleScript?

    init(appName: String, idProperty: String, durationScale: Double, queue: DispatchQueue) {
        self.appName = appName
        self.durationScale = durationScale
        self.queue = queue
        self.source = """
        set d to (ASCII character 31)
        tell application "System Events"
          set isRunning to (exists (processes where name is "\(appName)"))
        end tell
        if not isRunning then return "not-running"
        tell application "\(appName)"
          set s to (player state as string)
          if s is not "playing" and s is not "paused" then return "stopped"
          try
            set t to current track
            set nm to name of t
            set ar to artist of t
            set al to album of t
            set dur to duration of t
            set pos to player position
            set pid to (\(idProperty) of t)
            return "ok" & d & nm & d & ar & d & al & d & (dur as string) & d & (pos as string) & d & s & d & (pid as string)
          on error
            return "stopped"
          end try
        end tell
        """
    }

    func poll() -> NowPlaying {
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
        let src = "tell application \"\(appName)\" to \(command)"
        queue.async {
            guard let script = NSAppleScript(source: src) else { return }
            var err: NSDictionary?
            script.executeAndReturnError(&err)
        }
    }
}
