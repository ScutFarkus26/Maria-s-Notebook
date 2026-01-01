import Foundation

/// Helper responsible for persisting and retrieving the order of subjects and per-subject groups using UserDefaults.
struct FilterOrderStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    
    private static var shared = FilterOrderStore()
    
    private static let subjectOrderKey = "Lessons.SubjectOrder"
    private static let groupOrderPrefix = "Lessons.GroupOrder."
    
    private static var cachedSubjectOrder: [String]?
    private static var cachedGroupOrders: [String: [String]] = [:]
    
    /// Normalizes subject string by trimming whitespaces and lowercasing.
    private static func normalizedSubject(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    /// Loads the saved subject order from UserDefaults, filtering to existing subjects and appending any missing at the end preserving original order.
    static func loadSubjectOrder(existing: [String]) -> [String] {
        if let cached = cachedSubjectOrder {
            return mergeOrder(saved: cached, existing: existing)
        }
        guard let saved = shared.defaults.array(forKey: subjectOrderKey) as? [String] else {
            cachedSubjectOrder = existing
            return existing
        }
        let result = mergeOrder(saved: saved, existing: existing)
        cachedSubjectOrder = result
        return result
    }
    
    /// Saves the given subject order into UserDefaults and updates cache.
    static func saveSubjectOrder(_ order: [String]) {
        cachedSubjectOrder = order
        shared.defaults.set(order, forKey: subjectOrderKey)
    }
    
    /// Loads the saved group order for a given subject from UserDefaults, filtering to existing groups and appending any missing at the end preserving original order.
    static func loadGroupOrder(for subject: String, existing: [String]) -> [String] {
        let key = groupOrderPrefix + normalizedSubject(subject)
        if let cached = cachedGroupOrders[key] {
            return mergeOrder(saved: cached, existing: existing)
        }
        guard let saved = shared.defaults.array(forKey: key) as? [String] else {
            cachedGroupOrders[key] = existing
            return existing
        }
        let result = mergeOrder(saved: saved, existing: existing)
        cachedGroupOrders[key] = result
        return result
    }
    
    /// Saves the given group order for a subject into UserDefaults and updates cache.
    static func saveGroupOrder(_ order: [String], for subject: String) {
        let key = groupOrderPrefix + normalizedSubject(subject)
        cachedGroupOrders[key] = order
        shared.defaults.set(order, forKey: key)
    }
    
    /// Clears in-memory caches for subject and group orders.
    static func resetCache() {
        cachedSubjectOrder = nil
        cachedGroupOrders.removeAll()
    }

    /// Removes the persisted subject order from UserDefaults and clears the cache.
    static func clearSubjectOrder() {
        cachedSubjectOrder = nil
        shared.defaults.removeObject(forKey: subjectOrderKey)
    }

    /// Removes the persisted group order for a specific subject from UserDefaults and clears the cached entry.
    static func clearGroupOrder(for subject: String) {
        let key = groupOrderPrefix + normalizedSubject(subject)
        cachedGroupOrders.removeValue(forKey: key)
        shared.defaults.removeObject(forKey: key)
    }
    
    /// Merges saved order with existing items keeping saved order first, de-duplicating saved entries,
    /// and appending any missing existing items at the end. Uses Sets for efficient lookups.
    private static func mergeOrder(saved: [String], existing: [String]) -> [String] {
        let existingSet = Set(existing)

        // Deduplicate saved while preserving order and filter to items that still exist
        var seen = Set<String>()
        var filteredSaved: [String] = []
        filteredSaved.reserveCapacity(saved.count)
        for item in saved {
            if existingSet.contains(item), seen.insert(item).inserted {
                filteredSaved.append(item)
            }
        }

        // Append missing existing items efficiently
        let savedSet = Set(filteredSaved)
        let missing = existing.filter { !savedSet.contains($0) }

        return filteredSaved + missing
    }

    /// Allows tests to inject a custom UserDefaults instance.
    static func useDefaults(_ defaults: UserDefaults) {
        shared = FilterOrderStore(defaults: defaults)
        cachedSubjectOrder = nil
        cachedGroupOrders.removeAll()
    }
}
