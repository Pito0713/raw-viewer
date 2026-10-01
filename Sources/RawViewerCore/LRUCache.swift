/// 容量很小（幾十筆）的 LRU 快取，線性搜尋就夠用。
public struct LRUCache<Key: Hashable, Value> {
    public let capacity: Int
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []  // 最近使用的在最後

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public var count: Int { storage.count }

    /// 讀取但不更新使用順序（可以在 SwiftUI body 裡安全呼叫）。
    public func peek(_ key: Key) -> Value? {
        storage[key]
    }

    public mutating func touch(_ key: Key) {
        guard storage[key] != nil, let index = order.firstIndex(of: key) else { return }
        order.remove(at: index)
        order.append(key)
    }

    public mutating func insert(_ value: Value, for key: Key) {
        if storage.updateValue(value, forKey: key) != nil, let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
        while order.count > capacity {
            storage[order.removeFirst()] = nil
        }
    }

    public mutating func removeAll() {
        storage.removeAll()
        order.removeAll()
    }
}
