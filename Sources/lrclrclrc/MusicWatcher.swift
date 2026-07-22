import Foundation

struct NowPlaying {
    enum State { case ok, stopped, notRunning }
    var state: State = .notRunning
    var title = ""
    var artist = ""
    var album = ""
    var duration: Double = 0
    var position: Double = 0
    var isPlaying = false
    var trackId = ""
}

/// Reads the current track + playback position from the macOS Music app via
/// AppleScript. Fields are joined with the ASCII unit separator (0x1F) so
/// titles containing commas/quotes/newlines survive intact.
final class MusicWatcher {
    private static let sep = "\u{1F}"
    private let script: NSAppleScript?

    init() {
        script = NSAppleScript(source: MusicWatcher.source)
    }

    private static let source = """
    set d to (ASCII character 31)
    tell application "System Events"
      set isRunning to (exists (processes where name is "Music"))
    end tell
    if not isRunning then return "not-running"
    tell application "Music"
      set s to (player state as string)
      if s is not "playing" and s is not "paused" then return "stopped"
      try
        set t to current track
        set nm to name of t
        set ar to artist of t
        set al to album of t
        set dur to duration of t
        set pos to player position
        set pid to (persistent ID of t)
        return "ok" & d & nm & d & ar & d & al & d & (dur as string) & d & (pos as string) & d & s & d & pid
      on error
        return "stopped"
      end try
    end tell
    """

    /// Runs the script and parses the result. Call on the main thread.
    func poll() -> NowPlaying {
        guard let script else { return NowPlaying(state: .notRunning) }
        var err: NSDictionary?
        let desc = script.executeAndReturnError(&err)
        if err != nil { return NowPlaying(state: .notRunning) }

        let raw = desc.stringValue ?? ""
        if raw == "not-running" { return NowPlaying(state: .notRunning) }
        if !raw.hasPrefix("ok") { return NowPlaying(state: .stopped) }

        let parts = raw.components(separatedBy: MusicWatcher.sep)
        guard parts.count >= 8 else { return NowPlaying(state: .stopped) }

        var np = NowPlaying(state: .ok)
        np.title = parts[1]
        np.artist = parts[2]
        np.album = parts[3]
        np.duration = Double(parts[4]) ?? 0
        np.position = Double(parts[5]) ?? 0
        np.isPlaying = parts[6] == "playing"
        np.trackId = parts[7].isEmpty ? "\(parts[2])::\(parts[1])" : parts[7]
        return np
    }

    // MARK: - Playback commands

    func playPause() { run("playpause") }
    func nextTrack() { run("next track") }
    func previousTrack() { run("previous track") }

    private func run(_ command: String) {
        guard let script = NSAppleScript(source: "tell application \"Music\" to \(command)") else { return }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
    }
}
