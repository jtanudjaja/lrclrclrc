import SwiftUI
import AppKit

/// What the overlay's stage should render — one explicit design per case, so
/// nothing is improvised at runtime (spec Part 6).
enum StagePhase: Equatable {
    case idle                    // nothing playing / player closed / stopped
    case permission              // automation access denied
    case searching               // lyrics lookup in flight
    case notFound                // genuine LRCLIB miss
    case intro(countdown: Int, first: Bool) // synced: instrumental gap; first = before line 1
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
    /// Every player and whether it's enabled — the Preferences checkbox list.
    @Published private(set) var sourceStates: [SourceState] = []
    /// The enabled players, in menu order: the choices the Follow menu offers.
    @Published private(set) var enabledSources: [PlayerSourceKind] = []
    /// The one enabled player being followed; nil = automatic (whichever of the
    /// enabled ones is actually playing).
    @Published private(set) var followedSource: PlayerSourceKind?
    /// The idle stage's prompt — it names the players actually being followed
    /// rather than a hardcoded pair, so it stays true when one is switched off.
    @Published private(set) var sourceHint = ""

    // All AppleScript work (polls *and* playback commands) is confined to the
    // one serial pollQueue — NSAppleScript is not thread-safe, and a transport
    // press racing a background poll was a real crash/hang risk.
    private let pollQueue: DispatchQueue
    private let sources = SourceRegistry()
    // Built on first use, and only ever for a player we've located — see
    // SourceRegistry on why an unlocated player must never get a script.
    // Main-thread state: the poll queue is handed a ready-made list.
    private var players: [PlayerSourceKind: PlayerSource] = [:]
    private var active: PlayerSource?
    private var activeKind: PlayerSourceKind?

    private let overrides = OverrideStore()
    private let offsets = OffsetStore()
    private let cache = LRUCache<LyricsResult>(capacity: 200)
    private let diskCache = DiskLyricsCache()

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
    // After a seek, the player reports its old position for a beat; trusting it
    // would snap the lyrics back before jumping forward again (scrub bounce).
    private var seekGraceUntil = Date.distantPast
    // The timestamp the ♪ countdown is counting toward — its "stay on screen
    // down to 0" stickiness applies only to this gap, never a neighbouring one.
    private var introTarget: Double?

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var lyricsTask: Task<Void, Never>?
    private var observerTokens: [NSObjectProtocol] = []
    private var wakeToken: NSObjectProtocol?
    private var pollInFlight = false        // coalesce: skip if a read is running
    private var isActive = false            // last poll found a playing/paused track
    private var idleTickCounter = 0         // throttle polling while idle
    private var retryAttempt = 0            // fetch backoff: 5s, 10s, 20s, 40s, 60s cap
    private var notOkStreak = 0             // consecutive stopped/notRunning polls
    private var noSourceShown = false       // "nothing to follow" already on screen

    init() {
        pollQueue = DispatchQueue(label: "net.lrclrclrc.poll")
        publishSources()
    }

    deinit {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
        lyricsTask?.cancel()
        let center = DistributedNotificationCenter.default()
        for token in observerTokens { center.removeObserver(token) }
        if let wakeToken { NSWorkspace.shared.notificationCenter.removeObserver(wakeToken) }
    }

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
        for name in PlayerSourceKind.allCases.map(\.changeNotification) {
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.poll()
            }
            observerTokens.append(token)
        }
        // Re-anchor immediately when the Mac wakes from sleep.
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.poll() }
    }

    // MARK: - Polling (read on background, process on main)

    private func poll() {
        if pollInFlight { return } // coalesce overlapping requests
        // Assembled here, on main: `players` is main-thread state, and this is
        // also where "which source won last time" decides the order.
        let order = pollOrder()
        guard !order.isEmpty else { showNoSource(); return }
        pollInFlight = true
        pollQueue.async { [weak self] in
            guard let self else { return }
            let (np, kind) = Self.read(order)
            DispatchQueue.main.async {
                self.pollInFlight = false
                self.process(np, kind: kind)
            }
        }
    }

    /// The script runner for a source, built on first use. Returns nil for a
    /// player we couldn't locate — that one is never scripted at all.
    private func player(for kind: PlayerSourceKind) -> PlayerSource? {
        if let existing = players[kind] { return existing }
        guard let app = sources.located[kind] else { return nil }
        let made = AppleScriptPlayer(kind: kind, bundleID: app.bundleID, queue: pollQueue)
        players[kind] = made
        return made
    }

    /// Who gets polled. Pinning one player in the Follow menu means only that
    /// one is read; on automatic every enabled player is, the one that last
    /// produced a track first — so with two players open, whichever is already
    /// on screen keeps the stage until it stops, instead of list order quietly
    /// deciding for the user.
    private func pollOrder() -> [(PlayerSourceKind, PlayerSource)] {
        var kinds = sources.enabled
        if let followedSource {
            kinds = kinds.filter { $0 == followedSource }
        } else if let activeKind, let i = kinds.firstIndex(of: activeKind) {
            kinds.insert(kinds.remove(at: i), at: 0)
        }
        return kinds.compactMap { kind in player(for: kind).map { (kind, $0) } }
    }

    /// Runs on the poll queue. The first source with a live track wins; failing
    /// that, a permission refusal outranks plain silence, because it's the one
    /// state the user can do something about.
    private static func read(_ order: [(PlayerSourceKind, PlayerSource)]) -> (NowPlaying, PlayerSourceKind) {
        var fallback: (NowPlaying, PlayerSourceKind)?
        var denied: PlayerSourceKind?
        for (kind, player) in order {
            let np = player.poll()
            if np.state == .ok { return (np, kind) }
            if np.state == .permissionDenied, denied == nil { denied = kind }
            if fallback == nil { fallback = (np, kind) }
        }
        if let denied { return (NowPlaying(state: .permissionDenied), denied) }
        return fallback ?? (NowPlaying(state: .notRunning), .appleMusic)
    }

    /// Nothing is switched on (or nothing is installed) — the idle stage with
    /// `sourceHint` pointing at Preferences says the rest. Latched, because the
    /// poll timer keeps firing and republishing it would churn the overlay.
    private func showNoSource() {
        guard !noSourceShown else { return }
        noSourceShown = true
        isActive = false
        permissionNeeded = false
        title = "lrclrclrc"
        artist = ""
        clearTrack()
        status = ""
        lastTrackId = ""
        isPlaying = false
        playing = false
        stagePhase = .idle
    }

    private func process(_ np: NowPlaying, kind: PlayerSourceKind) {
        noSourceShown = false
        if np.state == .ok {
            active = players[kind]
            activeKind = kind
        }
        isActive = (np.state == .ok)
        if isActive { idleTickCounter = 0 }

        switch np.state {
        // Empty-state headers stay short (the stage explains the situation);
        // the overlay dims them per the idle designs.
        case .permissionDenied:
            permissionNeeded = true
            title = "lrclrclrc"
            artist = ""
            clearTrack()
            status = ""
            lastTrackId = ""
            isPlaying = false
            playing = false
            stagePhase = .permission
            return
        case .notRunning, .stopped:
            // Debounce: a single stopped/not-running read is often a transient
            // blip (track transition, AppleScript hiccup). Tearing the display
            // down on one blip made the header flash "Nothing playing" over
            // live lyrics and blink on reload — require two misses in a row.
            notOkStreak += 1
            if notOkStreak < 2, !lastTrackId.isEmpty { return }
            permissionNeeded = false
            title = "Nothing playing"
            artist = ""
            clearTrack()
            status = ""
            lastTrackId = ""
            isPlaying = false
            playing = false
            stagePhase = .idle
            return
        case .ok:
            notOkStreak = 0
            permissionNeeded = false
        }

        // Namespace keys by source so Apple Music / Spotify ids never collide.
        let key = "\(kind.rawValue)::\(np.trackId)"

        // Scrub-bounce guard: right after a seek the player still reports the
        // pre-seek position for a beat. Re-anchoring to that stale value would
        // snap the lyrics back and then forward again — inside the grace
        // window we trust our own clock (set optimistically by seek()).
        let inSeekGrace = key == lastTrackId && Date() < seekGraceUntil
        if !inSeekGrace {
            anchorPos = np.position
            anchorAt = Date()
        }
        playing = np.isPlaying
        isPlaying = np.isPlaying
        trackDuration = np.duration
        if np.isPlaying {
            lastPlayingAt = Date()
            if longIdle { longIdle = false }
        }

        guard key != lastTrackId else { return } // same song
        lastTrackId = key
        title = np.title
        artist = np.artist
        currentIndex = -1
        retryAttempt = 0 // fresh track, fresh backoff
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

        // Disk cache: survives relaunch/rebuild, so repeat plays are instant
        // and LRCLIB outages don't blank previously-heard songs.
        if let stored = diskCache.load(key) {
            cache.set(stored, for: key)
            apply(stored)
            return
        }

        status = "looking up lyrics…"
        stagePhase = .searching
        // Full teardown, not just the displayed strings — if the previous
        // track's `lines` lingered, the tick would re-assert a lyric phase and
        // paint the old song's lyrics under the new song's header for the whole
        // search (or failed-fetch backoff).
        clearTrack()
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
        // If the user pasted manual lyrics while this fetch (or its retry) was
        // in flight, the manual version wins — never stomp it.
        guard overrides.lyrics(for: key) == nil else { return }
        switch outcome {
        case .found(let res):
            retryAttempt = 0
            cache.set(res, for: key)
            diskCache.save(res, for: key)
            apply(res)
        case .notFound:
            retryAttempt = 0
            let empty = LyricsResult(synced: false, lines: [])
            cache.set(empty, for: key) // genuine miss — remember it
            apply(empty)
        case .failed:
            // Don't cache a transient failure; retry with exponential backoff
            // (5s → 10 → 20 → 40 → 60s cap) so a blip recovers fast but an
            // outage or rate limit isn't hammered — hammering a throttled API
            // just keeps you throttled.
            status = "couldn’t reach LRCLIB — retrying…"
            stagePhase = .searching
            scheduleRetry(for: key, meta: meta)
        }
    }

    private func scheduleRetry(for key: String, meta: TrackMeta) {
        let delay = min(60.0, 5.0 * pow(2.0, Double(retryAttempt)))
        retryAttempt += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  key == self.lastTrackId,          // track unchanged
                  !self.cache.contains(key),        // not resolved meanwhile
                  self.overrides.lyrics(for: key) == nil // no manual override
            else { return }
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
        introTarget = nil

        if lines.isEmpty {
            currentLine = "— no lyrics found —"
            prevLine = ""
            nextLine = ""
            status = ""
            stagePhase = .notFound
            return
        }

        if synced {
            status = "synced · lyrics from LRCLIB"
            stagePhase = .synced
            render(indexForTime(estimatedPosition()))
        } else {
            status = "unsynced · position estimated"
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
        // The timed line this tick could count toward: the first line while
        // still ahead of it, or the line after an empty instrumental marker.
        var target: Double?
        if index == -1 {
            target = lines.first?.time
        } else if index >= 0, index + 1 < lines.count, lines[index].text.isEmpty {
            target = lines[index + 1].time
        }

        // The 3s threshold only gates *entering* the countdown (tiny gaps
        // aren't worth announcing). Once on screen it runs down to 0 —
        // vanishing mid-count would read as a broken timer — but the
        // stickiness is keyed to the target's timestamp, so a seek into a
        // different sub-3s gap never inherits it. Seconds are rounded up so
        // "in 0:01" is the last thing shown, not "0:00".
        var phase: StagePhase = .synced
        if let target {
            let gap = target - position
            if gap > 3 || (gap > 0 && introTarget == target) {
                phase = .intro(countdown: Int(gap.rounded(.up)), first: index == -1)
            }
        }
        introTarget = (phase == .synced) ? nil : target
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

    /// Full lyric-state teardown for empty states. Clearing `lines` matters:
    /// while it's non-empty the 10Hz tick keeps re-asserting a lyric phase,
    /// which is how "Nothing playing" ended up captioning live lyrics.
    private func clearTrack() {
        lyricsTask?.cancel() // an in-flight fetch for a torn-down track is moot
        lines = []
        allLines = []
        synced = false
        isSynced = false
        currentIndex = -1
        currentLineIndex = -1
        introTarget = nil
        clearLines()
    }

    // MARK: - Playback controls

    // No active player means nothing has reported a track yet — there is
    // nothing to command, so these are no-ops rather than a guess at which
    // player the user meant.
    func playPause() { active?.playPause(); refreshSoon() }
    func nextTrack() { active?.nextTrack(); refreshSoon() }
    func previousTrack() { active?.previousTrack(); refreshSoon() }

    /// Seek playback to a timestamp (used by the full-lyrics view's tap-to-jump).
    func seek(to seconds: Double) {
        guard let active else { return }
        let target = max(0, seconds)
        active.seek(to: target)
        anchorPos = target // update the clock immediately for a snappy jump
        anchorAt = Date()
        seekGraceUntil = Date().addingTimeInterval(1.5) // ignore stale reports
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

    // MARK: - Sources

    /// Enable or disable a player. Enabling one we couldn't find is the only
    /// thing in the app that opens a file picker — and only then, so a Mac
    /// without Spotify never sees a "Where is Spotify?" dialog at all.
    /// Returns false if the user cancelled the picker or chose a non-app.
    @discardableResult
    func setSourceEnabled(_ enabled: Bool, for kind: PlayerSourceKind) -> Bool {
        if sources.setEnabled(enabled, for: kind) {
            sourcesChanged()
            return true
        }
        // Cancelling leaves the source off. Republish anyway so a checkbox that
        // already flipped itself in anticipation snaps back.
        guard enabled, let url = SourceRegistry.askForApp(kind) else {
            publishSources()
            return false
        }
        guard sources.adopt(url, as: kind) else {
            let alert = NSAlert()
            alert.messageText = "That doesn't look like an app."
            alert.informativeText = "Choose \(kind.displayName)'s .app bundle — usually in /Applications."
            alert.runModal()
            publishSources()
            return false
        }
        // The old runner, if any, was built around the previous bundle id.
        players[kind] = nil
        sourcesChanged()
        return true
    }

    /// Pin the lyrics to one enabled player, or nil for automatic.
    func followSource(_ kind: PlayerSourceKind?) {
        Settings.selectedSource = kind?.rawValue
        sourcesChanged()
    }

    /// Back to everything installed enabled and nothing pinned. Players are
    /// dropped too, so a hand-located app doesn't outlive the setting that
    /// pointed at it.
    func resetSources() {
        sources.reset()
        players.removeAll()
        active = nil
        activeKind = nil
        sourcesChanged()
    }

    private func sourcesChanged() {
        publishSources()
        noSourceShown = false
        lastTrackId = "" // force a reload from whatever we now follow
        poll()
    }

    private func publishSources() {
        sourceStates = sources.states
        enabledSources = sources.enabled
        // A pin only survives while its player is still enabled — disabling the
        // followed app drops back to automatic rather than following nothing.
        let pinned = Settings.selectedSource.flatMap(PlayerSourceKind.init(rawValue:))
        followedSource = pinned.flatMap { enabledSources.contains($0) ? $0 : nil }

        let names = (followedSource.map { [$0] } ?? enabledSources).map(\.displayName)
        switch names.count {
        case 0:
            sourceHint = "No music app is enabled — turn one on in Preferences"
        case 1:
            sourceHint = "Play something in \(names[0])"
        default:
            sourceHint = "Play something in " + names.dropLast().joined(separator: ", ")
                + " or " + names[names.count - 1]
        }
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
        diskCache.remove(key)
        applyRaw(text)
    }

    /// Drop the manual override for the current track and re-fetch normally.
    func clearManualLyrics() {
        let key = lastTrackId
        guard !key.isEmpty else { return }
        overrides.remove(for: key)
        cache.removeValue(forKey: key)
        diskCache.remove(key)
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
