// Maria's Notebook/Components/FilterOrderStore.swift

import Foundation

/// Helper responsible for persisting and retrieving the order of areas, per-area groups,
/// and per-area+sequence sections using UserDefaults.
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

    // The caches below hold the *saved* order, never the merged result. Merging drops
    // whatever the caller didn't pass in `existing`, so caching the result let one
    // narrowed call — the Checklist while its filter field is in use, the map under a
    // chip filter — throw away the saved position of everything absent at that moment.
    // Both screens then read that shortened list back and re-appended the missing
    // sections alphabetically, and the order stayed wrong for the rest of the launch.

    static func loadAreaOrder(existing: [String]) -> [String] {
        mergeOrder(saved: savedAreaOrder(), existing: existing)
    }

    private static func savedAreaOrder() -> [String] {
        if let cached = cachedAreaOrder { return cached }
        let saved = shared.defaults.array(forKey: areaOrderKey) as? [String] ?? []
        cachedAreaOrder = saved
        return saved
    }

    // MARK: Groups (Tracks)

    static func loadSequenceOrder(for area: String, existing: [String]) -> [String] {
        let key = groupOrderPrefix + normalized(area)
        if let cached = cachedSequenceOrders[key] {
            return mergeOrder(saved: cached, existing: existing)
        }
        let saved = shared.defaults.array(forKey: key) as? [String] ?? []
        cachedSequenceOrders[key] = saved
        return mergeOrder(saved: saved, existing: existing)
    }

    static func saveSequenceOrder(_ order: [String], for area: String) {
        let key = groupOrderPrefix + normalized(area)
        cachedSequenceOrders[key] = order
        shared.defaults.set(order, forKey: key)
    }

    // MARK: Sections

    static func loadSectionOrder(for area: String, sequence: String, existing: [String]) -> [String] {
        let key = sectionOrderPrefix + normalized(area) + "." + normalized(sequence)
        if let cached = cachedSectionOrders[key] {
            return mergeOrder(saved: cached, existing: existing)
        }
        let saved = shared.defaults.array(forKey: key) as? [String] ?? []
        cachedSectionOrders[key] = saved
        return mergeOrder(saved: saved, existing: existing)
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

    // MARK: Merge helper

    /// The saved order, narrowed to what the caller actually has, with anything the
    /// saved order doesn't mention appended in the caller's own order.
    ///
    /// Names are matched normalized rather than by exact string. A section saved as
    /// "Equivalence" and shown as "equivalence" is one section, and matching it
    /// literally read the second spelling as new and sent that whole band to the
    /// bottom of the grid — while the screen that happened to spell it the saved way
    /// still looked right. Two spellings of one name collapse to the first the caller
    /// listed, so neither grid draws the same band twice.
    private static func mergeOrder(saved: [String], existing: [String]) -> [String] {
        var unplaced: [String: String] = [:]
        var callerOrder: [String] = []
        callerOrder.reserveCapacity(existing.count)
        for item in existing {
            let key = normalized(item)
            guard unplaced[key] == nil else { continue }
            unplaced[key] = item
            callerOrder.append(item)
        }

        var result: [String] = []
        result.reserveCapacity(existing.count)
        for item in saved {
            if let spelling = unplaced.removeValue(forKey: normalized(item)) {
                result.append(spelling)
            }
        }
        result.append(contentsOf: callerOrder.filter { unplaced[normalized($0)] != nil })
        return result
    }
}
