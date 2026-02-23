// Maria's Notebook/Components/FilterOrderStore.swift

import Foundation

/// Helper responsible for persisting and retrieving the order of subjects, per-subject groups,
/// and per-subject+group subheadings using UserDefaults.
@MainActor
struct FilterOrderStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private static var shared = FilterOrderStore()

    private static let subjectOrderKey = "Lessons.SubjectOrder"
    private static let groupOrderPrefix = "Lessons.GroupOrder."
    private static let subheadingOrderPrefix = "Lessons.SubheadingOrder." // subject+group

    private static var cachedSubjectOrder: [String]?
    private static var cachedGroupOrders: [String: [String]] = [:]
    private static var cachedSubheadingOrders: [String: [String]] = [:]

    private static func normalized(_ s: String) -> String {
        s.normalizedForComparison()
    }

    // MARK: Subjects

    static func loadSubjectOrder(existing: [String]) -> [String] {
        if let cached = cachedSubjectOrder { return mergeOrder(saved: cached, existing: existing) }
        guard let saved = shared.defaults.array(forKey: subjectOrderKey) as? [String] else {
            cachedSubjectOrder = existing
            return existing
        }
        let result = mergeOrder(saved: saved, existing: existing)
        cachedSubjectOrder = result
        return result
    }

    static func saveSubjectOrder(_ order: [String]) {
        cachedSubjectOrder = order
        shared.defaults.set(order, forKey: subjectOrderKey)
    }

    // MARK: Groups (Tracks)

    static func loadGroupOrder(for subject: String, existing: [String]) -> [String] {
        let key = groupOrderPrefix + normalized(subject)
        if let cached = cachedGroupOrders[key] { return mergeOrder(saved: cached, existing: existing) }
        guard let saved = shared.defaults.array(forKey: key) as? [String] else {
            cachedGroupOrders[key] = existing
            return existing
        }
        let result = mergeOrder(saved: saved, existing: existing)
        cachedGroupOrders[key] = result
        return result
    }

    static func saveGroupOrder(_ order: [String], for subject: String) {
        let key = groupOrderPrefix + normalized(subject)
        cachedGroupOrders[key] = order
        shared.defaults.set(order, forKey: key)
    }

    // MARK: Subheadings

    static func loadSubheadingOrder(for subject: String, group: String, existing: [String]) -> [String] {
        let key = subheadingOrderPrefix + normalized(subject) + "." + normalized(group)
        if let cached = cachedSubheadingOrders[key] { return mergeOrder(saved: cached, existing: existing) }
        guard let saved = shared.defaults.array(forKey: key) as? [String] else {
            cachedSubheadingOrders[key] = existing
            return existing
        }
        let result = mergeOrder(saved: saved, existing: existing)
        cachedSubheadingOrders[key] = result
        return result
    }

    static func saveSubheadingOrder(_ order: [String], for subject: String, group: String) {
        let key = subheadingOrderPrefix + normalized(subject) + "." + normalized(group)
        cachedSubheadingOrders[key] = order
        shared.defaults.set(order, forKey: key)
    }

    // MARK: Cache control

    static func resetCache() {
        cachedSubjectOrder = nil
        cachedGroupOrders.removeAll()
        cachedSubheadingOrders.removeAll()
    }

    static func useDefaults(_ defaults: UserDefaults) {
        shared = FilterOrderStore(defaults: defaults)
        resetCache()
    }

    // MARK: Merge helper

    private static func mergeOrder(saved: [String], existing: [String]) -> [String] {
        let existingSet = Set(existing)

        var seen = Set<String>()
        var filteredSaved: [String] = []
        filteredSaved.reserveCapacity(saved.count)
        for item in saved {
            if existingSet.contains(item), seen.insert(item).inserted {
                filteredSaved.append(item)
            }
        }

        let savedSet = Set(filteredSaved)
        let missing = existing.filter { !savedSet.contains($0) }

        return filteredSaved + missing
    }
}
