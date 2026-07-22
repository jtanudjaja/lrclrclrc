import SwiftUI
import AppKit

/// What the overlay's stage should render — one explicit design per case, so
/// nothing is improvised at runtime (spec Part 6).
enum StagePhase: Equatable {
    case idle                    // nothing playing / player closed / stopped
    case permission              // automation access denied
    case searching               // lyrics lookup in flight
    case notFound                // genuine LRCLIB miss
    case intro(countdown: Int)   // synced: >3s of instrumental before the next line
    case synced                  // timed teleprompter
    case unsynced                // plain lyrics, position estimated
}

/// Owns playback state and drives the overlay. AppleScript reads run on a
/// background queue (so they never hitch the overlay animation); results are
/// published on the main thread. A 1s timer plus the players' change
/// notifications keep it responsive, and the ~10fps tick extrapolates the
/// position between polls so the highlighted line advances smoothly.
final class LyricsController: ObservableObject {
    @Published var title = "lrclrclrc"
    @Published var artist = "Play something…"
    @Published var prevLine = ""
    @Published var currentLine = ""
    @Published var nextLine = ""
    @Published var status = ""
    @Published var isPlaying = false
    @Published var permissionNeeded = false
    @Published private(set) var offset: Double = 0
    @Published private(set) var isSynced = false
    @Published private(set) var allLines: [LrcLine] = []
    @Published private(set) var currentLineIndex = -1
    @Published private(set) var stagePhase: StagePhase = .idle
    /// True after ~30s with nothing playing — the overlay fades to near-transparent.
    @Published private(set) var longIdle = false

    private let music: PlayerSource = AppleScriptPlayer(appName: "Music", idProperty: "persistent ID", durationScale: 1)
    private let spotify: PlayerSource = AppleScriptPlayer(appName: "Spotify", idProperty: "id", durationScale: 0.001)
    private var active: PlayerSource
    private var sourceKind = PlayerSourceKind(rawValue: Settings.source) ?? .auto

    private let overrides = OverrideStore()
    private let offsets = OffsetStore()
    private let cache = LRUCache<LyricsResult>(capacity: 200)

    private struct TrackMeta {
        let title: String
        let artist: String
        let album: String
        let duration: Double
    }

    private var lines: [LrcLine] = []
    private var synced = false
    private var currentIndex = -1
    private var lastTrackId = ""

    // Playback clock.
    private var anchorPos = 0.0
    private var anchorAt = Date()
    private var playing = false
    private var trackDuration = 0.0
    private var lastPlayingAt = Date()

    private let pollQueue = DispatchQueue(label: "net.lrclrclrc.poll")
    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var lyricsTask: Task<Void, Never>?
    private var pollInFlight = false        // coalesce: skip if a read is running
    private var isActive = false            // last poll found a playing/paused track
    private var idleTickCounter = 0         // throttle polling while idle

    init() { active = music }

    func start() {
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.timerPoll()
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        observePlayerNotifications()
    }

    /// While a track is active, poll every second; while idle, only every ~3s
    /// (change notifications still wake it instantly when playback resumes).
    private func timerPoll() {
        if isActive {
            poll()
        } else {
            idleTickCounter += 1
            if idleTickCounter >= 3 {
                idleTickCounter = 0
                poll()
            }
        }
        // Long-stop fade: nothing has *played* for 30s (paused counts).
        let idleNow = !playing && Date().timeIntervalSince(lastPlayingAt) > 30
        if idleNow != longIdle { longIdle = idleNow }
    }

    /// React instantly to track/state changes instead of waiting for the poll.
    private func observePlayerNotifications() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.poll()
            }
        }
        // Re-anchor immediately when the Mac wakes from sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.poll() }
    }

    // MARK: - Polling (read on background, process on main)

    private func poll() {
        if pollInFlight { return } // coalesce overlapping requests
        pollInFlight = true
        let preferred = sourceKind
        pollQueue.async { [weak self] in
            guard let self else { return }
            let (np, kind) = self.read(preferred: preferred)
            DispatchQueue.main.async {
                self.pollInFlight = false
                self.process(np, kind: kind)
            }
        }
    }

    /// Runs on the poll queue. Reads the chosen source (Auto tries Music, then
    /// Spotify), returning the reading and which source produced it.
    private func read(preferred: PlayerSourceKind) -> (NowPlaying, PlayerSourceKind) {
        switch preferred {
        case .appleMusic:
            return (music.poll(), .appleMusic)
        case .spotify:
            return (spotify.poll(), .spotify)
        case .auto:
            let m = music.poll()
            if m.state == .ok { return (m, .appleMusic) }
            let s = spotify.poll()
            if s.state == .ok { return (s, .spotify) }
            if m.state == .permissionDenied || s.state == .permissionDenied {
                return (NowPlaying(state: .permissionDenied), .appleMusic)
            }
            return (m, .appleMusic)
        }
    }

    private func process(_ np: NowPlaying, kind: PlayerSourceKind) {
        active = (kind == .spotify) ? spotify : music
        isActive = (np.state == .ok)
        if isActive { idleTickCounter = 0 }

        switch np.state {
        case .permissionDenied:
            permissionNeeded = true
            title = "lrclrclrc"
            artist = "Automation permission needed"
            clearLines()
            status = ""
            lastTrackId = ""
            isPlaying = false
            playing = false
            stagePhase = .permission
            return
        case .notRunning:
            permissionNeeded = false
            title = "lrclrclrc"
            artist = "No music playing"
            clearLines()
            status = ""
            lastTrackId = ""
            isPlaying = false
            playing = false
            stagePhase = .idle
            return
        case .stopped:
            permissionNeeded = false
            artist = "Nothing playing"
            clearLines()
            lastTrackId = ""
            isPlaying = false
            playing = false
            stagePhase = .idle
            return
        case .ok:
            permissionNeeded = false
        }

        anchorPos = np.position
        anchorAt = Date()
        playing = np.isPlaying
        isPlaying = np.isPlaying
        trackDuration = np.duration
        if np.isPlaying {
            lastPlayingAt = Date()
            if longIdle { longIdle = false }
        }

        // Namespace keys by source so Apple Music / Spotify ids never collide.
        let key = "\(kind.rawValue)::\(np.trackId)"
        guard key != lastTrackId else { return } // same song
        lastTrackId = key
        title = np.title
        artist = np.artist
        currentIndex = -1
        offset = offsets.offset(for: key)

        // A manual override wins over anything from the network.
        if let manual = overrides.lyrics(for: key) {
            applyRaw(manual)
            return
        }

        if let cached = cache.get(key) {
            apply(cached)
            return
        }

        status = "looking up lyrics…"
        stagePhase = .searching
        clearLines()
        fetchLyrics(for: key, meta: TrackMeta(
            title: np.title, artist: np.artist, album: np.album, duration: np.duration
        ))
    }

    // MARK: - Lyrics fetch (with retry on failure)

    private func fetchLyrics(for key: String, meta: TrackMeta) {
        lyricsTask?.cancel()
        lyricsTask = Task { [weak self] in
            let outcome = await LyricsService.fetch(
                title: meta.title, artist: meta.artist, album: meta.album, duration: meta.duration
            )
            guard let self else { return }
            await MainActor.run { self.handleFetch(outcome, for: key, meta: meta) }
        }
    }

    private func handleFetch(_ outcome: FetchOutcome, for key: String, meta: TrackMeta) {
        guard key == lastTrackId else { return } // track changed while fetching
        switch outcome {
        case .found(let res):
            cache.set(res, for: key)
            apply(res)
        case .notFound:
            let empty = LyricsResult(synced: false, lines: [])
            cache.set(empty, for: key) // genuine miss — remember it
            apply(empty)
        case .failed:
            // Don't cache a transient failure; retry so a network blip recovers.
            status = "couldn’t reach LRCLIB — retrying…"
            stagePhase = .searching
            scheduleRetry(for: key, meta: meta)
        }
    }

    private func scheduleRetry(for key: String, meta: TrackMeta) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, key == self.lastTrackId, !self.cache.contains(key) else { return }
            self.fetchLyrics(for: key, meta: meta)
        }
    }

    // MARK: - Rendering / sync

    private func apply(_ res: LyricsResult) {
        lines = res.lines
        allLines = res.lines
        synced = res.synced && lines.contains { $0.time != nil }
        isSynced = synced
        currentIndex = -1
        currentLineIndex = -1

        if lines.isEmpty {
            currentLine = "— no lyrics found —"
            prevLine = ""
            nextLine = ""
            status = ""
            stagePhase = .notFound
            return
        }

        if synced {
            status = "synced · LRCLIB"
            stagePhase = .synced
            render(indexForTime(estimatedPosition()))
        } else {
            status = "unsynced · LRCLIB"
            stagePhase = .unsynced
            let est = estimatedUnsyncedIndex()
            currentIndex = est
            render(est)
        }
    }

    private func tick() {
        guard !lines.isEmpty else { return }
        if synced {
            let pos = estimatedPosition()
            let idx = indexForTime(pos)
            if idx != currentIndex {
                currentIndex = idx
                render(idx)
            }
            updateGapPhase(position: pos, index: idx)
        } else {
            // Unsynced: estimate the reading position from elapsed ÷ duration.
            let est = estimatedUnsyncedIndex()
            if est != currentIndex {
                currentIndex = est
                render(est)
            }
        }
    }

    /// Proportional line estimate for unsynced lyrics (spec Part 6).
    private func estimatedUnsyncedIndex() -> Int {
        guard trackDuration > 0, !lines.isEmpty else { return 0 }
        let fraction = max(0, min(1, estimatedPosition() / trackDuration))
        return min(lines.count - 1, Int(fraction * Double(lines.count)))
    }

    /// Intro/instrumental detection: more than a few seconds of silence before
    /// the next timed line → the ♪ countdown phase (spec Part 6). Only the
    /// countdown's whole-second value is published, so this stays ~1Hz.
    private func updateGapPhase(position: Double, index: Int) {
        var phase: StagePhase = .synced
        if index == -1, let first = lines.first?.time, first - position > 3 {
            phase = .intro(countdown: max(0, Int(first - position)))
        } else if index >= 0, index + 1 < lines.count,
                  lines[index].text.isEmpty,
                  let next = lines[index + 1].time, next - position > 3 {
            phase = .intro(countdown: max(0, Int(next - position)))
        }
        if phase != stagePhase { stagePhase = phase }
    }

    private func estimatedPosition() -> Double {
        let base = playing ? anchorPos + Date().timeIntervalSince(anchorAt) : anchorPos
        return base + offset
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
        currentLineIndex = index
        currentLine = (index >= 0 && index < lines.count) ? lines[index].text : (synced ? "♪" : "")
        prevLine = (index - 1 >= 0 && index - 1 < lines.count) ? lines[index - 1].text : ""
        nextLine = (index + 1 >= 0 && index + 1 < lines.count) ? lines[index + 1].text : ""
    }

    private func clearLines() {
        prevLine = ""
        currentLine = ""
        nextLine = ""
    }

    // MARK: - Playback controls

    func playPause() { active.playPause(); refreshSoon() }
    func nextTrack() { active.nextTrack(); refreshSoon() }
    func previousTrack() { active.previousTrack(); refreshSoon() }

    /// Seek playback to a timestamp (used by the full-lyrics view's tap-to-jump).
    func seek(to seconds: Double) {
        let target = max(0, seconds)
        active.seek(to: target)
        anchorPos = target // update the clock immediately for a snappy jump
        anchorAt = Date()
        resync()
        refreshSoon()
    }

    /// Seek to a lyric line: timed lines jump to their timestamp; unsynced
    /// lines seek proportionally (line i of n → i/n × duration) — used by the
    /// overlay's click- and scrub-to-seek.
    func seek(toLine index: Int) {
        guard index >= 0, index < lines.count else { return }
        if let t = lines[index].time {
            seek(to: max(0, t))
        } else if trackDuration > 0 {
            seek(to: Double(index) / Double(max(1, lines.count)) * trackDuration)
        }
    }

    /// The timestamp a line would seek to (for the scrub chip); nil when the
    /// track has no usable target.
    func seekTarget(forLine index: Int) -> Double? {
        guard index >= 0, index < lines.count else { return nil }
        if let t = lines[index].time { return t }
        guard trackDuration > 0 else { return nil }
        return Double(index) / Double(max(1, lines.count)) * trackDuration
    }

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

    // MARK: - Sync offset (per track)

    func nudgeOffset(_ delta: Double) {
        guard !lastTrackId.isEmpty else { return }
        offset = min(max(offset + delta, -10), 10)
        offsets.set(offset, for: lastTrackId)
        resync()
    }

    func resetOffset() {
        guard !lastTrackId.isEmpty else { return }
        offset = 0
        offsets.set(0, for: lastTrackId)
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
        let key = lastTrackId
        guard !key.isEmpty else { return }
        overrides.set(text, for: key)
        cache.removeValue(forKey: key)
        applyRaw(text)
    }

    /// Drop the manual override for the current track and re-fetch normally.
    func clearManualLyrics() {
        let key = lastTrackId
        guard !key.isEmpty else { return }
        overrides.remove(for: key)
        cache.removeValue(forKey: key)
        lastTrackId = "" // force the next poll to reload
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
}
