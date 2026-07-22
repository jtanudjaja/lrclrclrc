import SwiftUI
import AppKit

/// Owns playback state and drives the overlay. Polls Music once a second and
/// extrapolates the position at ~10fps between polls so the highlighted line
/// advances smoothly. Timers run on the main run loop, so `@Published` writes
/// happen on the main thread.
final class LyricsController: ObservableObject {
    @Published var title = "lrclrclrc"
    @Published var artist = "Play something in Apple Music…"
    @Published var prevLine = ""
    @Published var currentLine = ""
    @Published var nextLine = ""
    @Published var status = ""
    @Published var isPlaying = false
    @Published var permissionNeeded = false

    private let music: PlayerSource = AppleScriptPlayer(appName: "Music", idProperty: "persistent ID", durationScale: 1)
    private let spotify: PlayerSource = AppleScriptPlayer(appName: "Spotify", idProperty: "id", durationScale: 0.001)
    private var active: PlayerSource
    private var sourceKind = PlayerSourceKind(rawValue: Settings.source) ?? .auto

    private let overrides = OverrideStore()
    private var syncOffset = Settings.syncOffset

    private var lines: [LrcLine] = []
    private var synced = false
    private var currentIndex = -1
    private var lastTrackId = ""
    private var cache: [String: LyricsResult] = [:]

    init() { active = music }

    // Playback clock.
    private var anchorPos = 0.0
    private var anchorAt = Date()
    private var playing = false

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var lyricsTask: Task<Void, Never>?

    func start() {
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    // MARK: - Polling

    private func poll() {
        let (np, watcher) = readActive()
        active = watcher
        switch np.state {
        case .permissionDenied:
            permissionNeeded = true
            title = "lrclrclrc"
            artist = "Automation permission needed"
            clearLines()
            status = ""
            lastTrackId = ""
            isPlaying = false
            return
        case .notRunning:
            permissionNeeded = false
            title = "lrclrclrc"
            artist = "No music playing"
            clearLines()
            status = ""
            lastTrackId = ""
            isPlaying = false
            return
        case .stopped:
            permissionNeeded = false
            artist = "Nothing playing"
            clearLines()
            lastTrackId = ""
            isPlaying = false
            return
        case .ok:
            permissionNeeded = false
        }

        anchorPos = np.position
        anchorAt = Date()
        playing = np.isPlaying
        isPlaying = np.isPlaying

        guard np.trackId != lastTrackId else { return } // same song
        lastTrackId = np.trackId
        title = np.title
        artist = np.artist
        currentIndex = -1

        // A manual override wins over anything from the network.
        if let manual = overrides.lyrics(for: np.trackId) {
            applyRaw(manual)
            return
        }

        if let cached = cache[np.trackId] {
            apply(cached)
            return
        }

        status = "looking up lyrics…"
        clearLines()

        lyricsTask?.cancel()
        let id = np.trackId
        let title = np.title, artist = np.artist, album = np.album, duration = np.duration
        lyricsTask = Task { [weak self] in
            let result = await LyricsService.fetch(
                title: title, artist: artist, album: album, duration: duration
            )
            guard let self else { return }
            await MainActor.run {
                let res = result ?? LyricsResult(synced: false, lines: [])
                self.cache[id] = res
                if id == self.lastTrackId { self.apply(res) }
            }
        }
    }

    // MARK: - Rendering / sync

    private func apply(_ res: LyricsResult) {
        lines = res.lines
        synced = res.synced && lines.contains { $0.time != nil }
        currentIndex = -1

        if lines.isEmpty {
            currentLine = "— no lyrics found —"
            prevLine = ""
            nextLine = ""
            status = ""
            return
        }

        if synced {
            status = "synced · LRCLIB"
            render(indexForTime(estimatedPosition()))
        } else {
            status = "unsynced · LRCLIB"
            prevLine = ""
            currentLine = lines[0].text
            nextLine = lines.count > 1 ? lines[1].text : ""
        }
    }

    // MARK: - Playback controls

    func playPause() { active.playPause(); refreshSoon() }
    func nextTrack() { active.nextTrack(); refreshSoon() }
    func previousTrack() { active.previousTrack(); refreshSoon() }

    /// Give the player a moment to update, then re-poll so state/track catches up.
    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.poll()
        }
    }

    // MARK: - Source

    var currentSource: PlayerSourceKind { sourceKind }

    func setSource(_ kind: PlayerSourceKind) {
        sourceKind = kind
        Settings.source = kind.rawValue
        lastTrackId = "" // force reload from the newly selected source
        poll()
    }

    /// Resolve the now-playing reading and the source that produced it.
    private func readActive() -> (NowPlaying, PlayerSource) {
        switch sourceKind {
        case .appleMusic:
            return (music.poll(), music)
        case .spotify:
            return (spotify.poll(), spotify)
        case .auto:
            let m = music.poll()
            if m.state == .ok { return (m, music) }
            let s = spotify.poll()
            if s.state == .ok { return (s, spotify) }
            if m.state == .permissionDenied || s.state == .permissionDenied {
                return (NowPlaying(state: .permissionDenied), active)
            }
            return (m, music)
        }
    }

    // MARK: - Sync offset

    var offset: Double { syncOffset }

    func nudgeOffset(_ delta: Double) {
        syncOffset = min(max(syncOffset + delta, -10), 10)
        Settings.syncOffset = syncOffset
        resync()
    }

    func resetOffset() {
        syncOffset = 0
        Settings.syncOffset = 0
        resync()
    }

    private func resync() {
        guard synced, !lines.isEmpty else { return }
        currentIndex = -1
        let idx = indexForTime(estimatedPosition())
        currentIndex = idx
        render(idx)
    }

    // MARK: - Permissions

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Manual override

    /// True when a song is playing (so an override can be keyed to it).
    var hasCurrentTrack: Bool { !lastTrackId.isEmpty }

    /// Apply and persist user-pasted lyrics for the current track.
    func applyManualLyrics(_ text: String) {
        let trackId = lastTrackId
        guard !trackId.isEmpty else { return }
        overrides.set(text, for: trackId)
        cache.removeValue(forKey: trackId)
        applyRaw(text)
    }

    /// Drop the manual override for the current track and re-fetch normally.
    func clearManualLyrics() {
        let trackId = lastTrackId
        guard !trackId.isEmpty else { return }
        overrides.remove(for: trackId)
        cache.removeValue(forKey: trackId)
        lastTrackId = "" // force the next poll to reload from the network
    }

    /// Parse pasted text (timed `.lrc` if it has timestamps, else plain) and show it.
    private func applyRaw(_ text: String) {
        let parsed = LRCParser.parse(text)
        let result: LyricsResult
        if !parsed.isEmpty {
            result = LyricsResult(synced: true, lines: parsed)
        } else {
            let plain = text
                .components(separatedBy: .newlines)
                .map { LrcLine(time: nil, text: $0.trimmingCharacters(in: .whitespaces)) }
            result = LyricsResult(synced: false, lines: plain)
        }
        apply(result)
        if !result.lines.isEmpty {
            status = synced ? "manual · synced" : "manual"
        }
    }

    private func tick() {
        guard synced, !lines.isEmpty else { return }
        let idx = indexForTime(estimatedPosition())
        if idx != currentIndex {
            currentIndex = idx
            render(idx)
        }
    }

    private func estimatedPosition() -> Double {
        let base = playing ? anchorPos + Date().timeIntervalSince(anchorAt) : anchorPos
        return base + syncOffset
    }

    /// Last line whose timestamp is <= t (binary search).
    private func indexForTime(_ t: Double) -> Int {
        var lo = 0, hi = lines.count - 1, ans = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if (lines[mid].time ?? 0) <= t {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return ans
    }

    private func render(_ index: Int) {
        currentLine = (index >= 0 && index < lines.count) ? lines[index].text : (synced ? "♪" : "")
        prevLine = (index - 1 >= 0 && index - 1 < lines.count) ? lines[index - 1].text : ""
        nextLine = (index + 1 >= 0 && index + 1 < lines.count) ? lines[index + 1].text : ""
    }

    private func clearLines() {
        prevLine = ""
        currentLine = ""
        nextLine = ""
    }
}
