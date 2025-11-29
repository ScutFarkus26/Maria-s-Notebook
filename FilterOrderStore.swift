import Foundation

/// Helper responsible for persisting and retrieving the order of subjects and per-subject groups using UserDefaults.
struct FilterOrderStore {
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
        guard let saved = UserDefaults.standard.array(forKey: subjectOrderKey) as? [String] else {
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
        UserDefaults.standard.set(order, forKey: subjectOrderKey)
    }
    
    /// Loads the saved group order for a given subject from UserDefaults, filtering to existing groups and appending any missing at the end preserving original order.
    static func loadGroupOrder(for subject: String, existing: [String]) -> [String] {
        let key = groupOrderPrefix + normalizedSubject(subject)
        if let cached = cachedGroupOrders[key] {
            return mergeOrder(saved: cached, existing: existing)
        }
        guard let saved = UserDefaults.standard.array(forKey: key) as? [String] else {
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
        UserDefaults.standard.set(order, forKey: key)
    }
    
    /// Merges saved order with existing items keeping saved order first and appending missing existing items at the end.
    private static func mergeOrder(saved: [String], existing: [String]) -> [String] {
        let existingSet = Set(existing)
        let filteredSaved = saved.filter { existingSet.contains($0) }
        let missing = existing.filter { !filteredSaved.contains($0) }
        return filteredSaved + missing
    }
}
