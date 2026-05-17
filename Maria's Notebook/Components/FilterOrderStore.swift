// Maria's Notebook/Components/FilterOrderStore.swift

import Foundation

/// Helper responsible for persisting and retrieving the order of areas, per-area groups,
/// and per-area+sequence sections using UserDefaults.
@MainActor
struct FilterOrderStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private static var shared = FilterOrderStore()

    private static let areaOrderKey = "Lessons.AreaOrder"
    private static let groupOrderPrefix = "Lessons.SequenceOrder."
    private static let sectionOrderPrefix = "Lessons.SectionOrder." // area+sequence

    private static var cachedAreaOrder: [String]?
    private static var cachedSequenceOrders: [String: [String]] = [:]
    private static var cachedSectionOrders: [String: [String]] = [:]

    private static func normalized(_ s: String) -> String {
        s.normalizedForComparison()
    }

    // MARK: Areas

    static func loadAreaOrder(existing: [String]) -> [String] {
        if let cached = cachedAreaOrder { return mergeOrder(saved: cached, existing: existing) }
        guard let saved = shared.defaults.array(forKey: areaOrderKey) as? [String] else {
            cachedAreaOrder = existing
            return existing
        }
        let result = mergeOrder(saved: saved, existing: existing)
        cachedAreaOrder = result
        return result
    }

    static func saveAreaOrder(_ order: [String]) {
        cachedAreaOrder = order
        shared.defaults.set(order, forKey: areaOrderKey)
    }

    // MARK: Groups (Tracks)

    static func loadSequenceOrder(for area: String, existing: [String]) -> [String] {
        let key = groupOrderPrefix + normalized(area)
        if let cached = cachedSequenceOrders[key] { return mergeOrder(saved: cached, existing: existing) }
        guard let saved = shared.defaults.array(forKey: key) as? [String] else {
            cachedSequenceOrders[key] = existing
            return existing
        }
        let result = mergeOrder(saved: saved, existing: existing)
        cachedSequenceOrders[key] = result
        return result
    }

    static func saveSequenceOrder(_ order: [String], for area: String) {
        let key = groupOrderPrefix + normalized(area)
        cachedSequenceOrders[key] = order
        shared.defaults.set(order, forKey: key)
    }

    // MARK: Sections

    static func loadSectionOrder(for area: String, sequence: String, existing: [String]) -> [String] {
        let key = sectionOrderPrefix + normalized(area) + "." + normalized(sequence)
        if let cached = cachedSectionOrders[key] { return mergeOrder(saved: cached, existing: existing) }
        guard let saved = shared.defaults.array(forKey: key) as? [String] else {
            cachedSectionOrders[key] = existing
            return existing
        }
        let result = mergeOrder(saved: saved, existing: existing)
        cachedSectionOrders[key] = result
        return result
    }

    static func saveSectionOrder(_ order: [String], for area: String, sequence: String) {
        let key = sectionOrderPrefix + normalized(area) + "." + normalized(sequence)
        cachedSectionOrders[key] = order
        shared.defaults.set(order, forKey: key)
    }

    // MARK: Cache control

    static func resetCache() {
        cachedAreaOrder = nil
        cachedSequenceOrders.removeAll()
        cachedSectionOrders.removeAll()
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
