import Foundation

/// A small least-recently-used cache keyed by String. Bounds memory so the
/// lyrics cache doesn't grow without limit over a long listening session.
/// Not thread-safe — use from a single (main) thread.
final class LRUCache<Value> {
    private let capacity: Int
    private var store: [String: Value] = [:]
    private var order: [String] = [] // least-recent first, most-recent last

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func get(_ key: String) -> Value? {
        guard let value = store[key] else { return nil }
        touch(key)
        return value
    }

    func contains(_ key: String) -> Bool {
        store[key] != nil
    }

    func set(_ value: Value, for key: String) {
        store[key] = value
        touch(key)
        while order.count > capacity {
            let oldest = order.removeFirst()
            store[oldest] = nil
        }
    }

    func removeValue(forKey key: String) {
        store[key] = nil
        order.removeAll { $0 == key }
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
