import Foundation

struct LyricsResult {
    let synced: Bool
    let lines: [LrcLine]
}

/// Fetches lyrics from LRCLIB (https://lrclib.net) — free, no API key.
/// Tries the exact `/api/get` signature first, then falls back to `/api/search`.
enum LyricsService {
    private static let userAgent =
        "lrclrclrc/0.1.0 (https://github.com/jtanudjaja/lrclrclrc)"

    private struct Record: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    static func fetch(title: String, artist: String, album: String, duration: Double) async -> LyricsResult? {
        guard !title.isEmpty, !artist.isEmpty else { return nil }

        var record = await get(title: title, artist: artist, album: album, duration: duration)
        if record == nil { record = await search(title: title, artist: artist) }
        guard let record else { return nil }

        if let synced = record.syncedLyrics {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return LyricsResult(synced: true, lines: lines) }
        }
        if let plain = record.plainLyrics {
            let lines = plain
                .components(separatedBy: .newlines)
                .map { LrcLine(time: nil, text: $0.trimmingCharacters(in: .whitespaces)) }
            return LyricsResult(synced: false, lines: lines)
        }
        return nil
    }

    // MARK: - Endpoints

    private static func get(title: String, artist: String, album: String, duration: Double) async -> Record? {
        guard var comps = URLComponents(string: "https://lrclib.net/api/get") else { return nil }
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        comps.queryItems = items
        guard let url = comps.url, let data = await request(url) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private static func search(title: String, artist: String) async -> Record? {
        guard var comps = URLComponents(string: "https://lrclib.net/api/search") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = comps.url, let data = await request(url) else { return nil }
        guard let results = try? JSONDecoder().decode([Record].self, from: data) else { return nil }
        return results.first(where: { $0.syncedLyrics != nil })
            ?? results.first(where: { $0.plainLyrics != nil })
            ?? results.first
    }

    private static func request(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
