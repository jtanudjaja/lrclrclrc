import SwiftUI

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

    private let watcher = MusicWatcher()

    private var lines: [LrcLine] = []
    private var synced = false
    private var currentIndex = -1
    private var lastTrackId = ""
    private var cache: [String: LyricsResult] = [:]

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
        let np = watcher.poll()
        switch np.state {
        case .notRunning:
            title = "lrclrclrc"
            artist = "Apple Music isn’t running"
            clearLines()
            status = ""
            lastTrackId = ""
            return
        case .stopped:
            artist = "Nothing playing"
            clearLines()
            lastTrackId = ""
            return
        case .ok:
            break
        }

        anchorPos = np.position
        anchorAt = Date()
        playing = np.isPlaying

        guard np.trackId != lastTrackId else { return } // same song
        lastTrackId = np.trackId
        title = np.title
        artist = np.artist
        currentIndex = -1

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

    private func tick() {
        guard synced, !lines.isEmpty else { return }
        let idx = indexForTime(estimatedPosition())
        if idx != currentIndex {
            currentIndex = idx
            render(idx)
        }
    }

    private func estimatedPosition() -> Double {
        playing ? anchorPos + Date().timeIntervalSince(anchorAt) : anchorPos
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
