import Foundation

/// Persists a per-track timing offset (seconds), keyed by the player's stable
/// track id, so each song keeps its own sync correction. Backed by UserDefaults.
final class OffsetStore {
    private let key = "trackOffsets"
    private var map: [String: Double]

    init() {
        map = (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }

    func offset(for id: String) -> Double {
        map[id] ?? 0
    }

    func set(_ value: Double, for id: String) {
        if value == 0 {
            map.removeValue(forKey: id) // don't store no-ops
        } else {
            map[id] = value
        }
        UserDefaults.standard.set(map, forKey: key)
    }
}
