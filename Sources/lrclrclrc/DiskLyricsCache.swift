import Foundation
import CryptoKit

/// Disk-backed lyrics store under `~/Library/Caches/lrclrclrc/` — one small
/// JSON file per track, keyed by a hash of the track key. Survives relaunches
/// and rebuilds, keeps repeat plays instant, and rides out LRCLIB outages.
///
/// Only real lyrics are persisted: a "not on LRCLIB" miss is remembered for
/// the session (memory cache) but re-checked next launch, in case the song
/// gets added. Pruned least-recently-played beyond `capacity`. All writes and
/// pruning run on a background queue; reads are a single tiny file.
final class DiskLyricsCache {
    private let dir: URL
    private let io = DispatchQueue(label: "net.lrclrclrc.diskcache", qos: .utility)
    private let capacity: Int

    init(capacity: Int = 300) {
        self.capacity = capacity
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        dir = base.appendingPathComponent("lrclrclrc", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name + ".json")
    }

    func load(_ key: String) -> LyricsResult? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(LyricsResult.self, from: data),
              !result.lines.isEmpty else { return nil }
        // Touch so pruning treats it as recently played.
        io.async {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        }
        return result
    }

    func save(_ result: LyricsResult, for key: String) {
        guard !result.lines.isEmpty else { return } // never persist misses
        let url = fileURL(for: key)
        io.async { [dir, capacity] in
            if let data = try? JSONEncoder().encode(result) {
                try? data.write(to: url, options: .atomic)
            }
            // Prune least-recently-played beyond capacity.
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
            ), files.count > capacity else { return }
            let dated = files
                .compactMap { url -> (URL, Date)? in
                    let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                    return date.map { (url, $0) }
                }
                .sorted { $0.1 < $1.1 }
            for (old, _) in dated.prefix(max(0, dated.count - capacity)) {
                try? fm.removeItem(at: old)
            }
        }
    }

    func remove(_ key: String) {
        let url = fileURL(for: key)
        io.async { try? FileManager.default.removeItem(at: url) }
    }
}
