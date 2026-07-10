import Foundation

@MainActor
enum RecentPresentationCache {
    struct Key: Hashable {
        let day: Date
        let windowDays: Int
    }

    private static let maxEntries = 8
    private static var values: [Key: Set<UUID>] = [:]
    private static var order: [Key] = []

    static func value(for key: Key) -> Set<UUID>? {
        values[key]
    }

    static func store(_ value: Set<UUID>, for key: Key) {
        values[key] = value
        if !order.contains(key) { order.append(key) }
        if order.count > maxEntries, let oldest = order.first {
            order.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }
}
