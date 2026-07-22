import Foundation

struct LyricsResult {
    let synced: Bool
    let lines: [LrcLine]
}

/// Distinguishes a real "not on LRCLIB" from a transient request failure, so
/// callers can cache the former but retry the latter.
enum FetchOutcome {
    case found(LyricsResult)
    case notFound
    case failed
}

/// Fetches lyrics from LRCLIB (https://lrclib.net) — free, no API key.
/// Tries the exact `/api/get` signature first, then falls back to `/api/search`,
/// picking the closest-duration candidate.
enum LyricsService {
    private static let userAgent =
        "lrclrclrc/0.1.0 (https://github.com/jtanudjaja/lrclrclrc)"

    private struct Record: Decodable {
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private enum HTTPResult {
        case ok(Data)
        case notFound
        case failed
    }

    static func fetch(title: String, artist: String, album: String, duration: Double) async -> FetchOutcome {
        guard !title.isEmpty, !artist.isEmpty else { return .notFound }
        let got = await get(title: title, artist: artist, album: album, duration: duration)
        switch got {
        case .found, .failed:
            return got // a network failure on /get would just fail again on /search
        case .notFound:
            return await search(title: title, artist: artist, duration: duration)
        }
    }

    // MARK: - Endpoints

    private static func get(title: String, artist: String, album: String, duration: Double) async -> FetchOutcome {
        guard var comps = URLComponents(string: "https://lrclib.net/api/get") else { return .failed }
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        comps.queryItems = items
        guard let url = comps.url else { return .failed }

        switch await request(url) {
        case .failed: return .failed
        case .notFound: return .notFound
        case .ok(let data):
            guard let rec = try? JSONDecoder().decode(Record.self, from: data) else { return .notFound }
            return outcome(from: rec)
        }
    }

    private static func search(title: String, artist: String, duration: Double) async -> FetchOutcome {
        guard var comps = URLComponents(string: "https://lrclib.net/api/search") else { return .failed }
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = comps.url else { return .failed }

        switch await request(url) {
        case .failed: return .failed
        case .notFound: return .notFound
        case .ok(let data):
            guard let results = try? JSONDecoder().decode([Record].self, from: data), !results.isEmpty else {
                return .notFound
            }
            return outcome(from: bestMatch(results, duration: duration))
        }
    }

    /// Prefer a candidate with synced lyrics, then the closest duration to the
    /// playing track (so live/remix versions don't beat the studio cut).
    private static func bestMatch(_ results: [Record], duration: Double) -> Record {
        func score(_ r: Record) -> (Int, Double) {
            let syncedRank = (r.syncedLyrics?.isEmpty == false) ? 0 : 1
            let durDelta = (duration > 0 && r.duration != nil)
                ? abs((r.duration ?? 0) - duration)
                : .greatestFiniteMagnitude
            return (syncedRank, durDelta)
        }
        return results.min(by: { score($0) < score($1) }) ?? results[0]
    }

    private static func outcome(from rec: Record) -> FetchOutcome {
        if let synced = rec.syncedLyrics {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .found(LyricsResult(synced: true, lines: lines)) }
        }
        if let plain = rec.plainLyrics {
            let lines = plain
                .components(separatedBy: .newlines)
                .map { LrcLine(time: nil, text: $0.trimmingCharacters(in: .whitespaces)) }
            return .found(LyricsResult(synced: false, lines: lines))
        }
        return .notFound
    }

    private static func request(_ url: URL) async -> HTTPResult {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .failed }
            if http.statusCode == 404 { return .notFound }
            if !(200...299).contains(http.statusCode) { return .failed }
            return .ok(data)
        } catch {
            return .failed
        }
    }
}
