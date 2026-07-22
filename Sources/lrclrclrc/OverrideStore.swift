import Foundation

/// Persists user-supplied lyrics, keyed by the Music app's persistent track id,
/// so a manual override sticks across track changes and app relaunches.
/// Backed by UserDefaults (the texts are small).
final class OverrideStore {
    private let key = "manualLyricsOverrides"
    private var map: [String: String]

    init() {
        map = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    func lyrics(for id: String) -> String? {
        guard let text = map[id], !text.isEmpty else { return nil }
        return text
    }

    func set(_ text: String, for id: String) {
        map[id] = text
        persist()
    }

    func remove(for id: String) {
        map.removeValue(forKey: id)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(map, forKey: key)
    }
}
