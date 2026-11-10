// Cosmic Daybook/Components/FilterOrderStore.swift

import Combine
import Foundation

/// Helper responsible for persisting and retrieving the order of areas and of each area's
/// sequences (sub-areas). Sections have no stored order: they follow their lessons
/// (`LessonSectionGrouping`). The keys an older build wrote for them
/// ("Lessons.SectionOrder.…") are left unread.
///
/// A sub-area order syncs between the guide's devices through `SyncedPreferencesStore`
/// (iCloud key-value storage) since 2026-11-09; before that it lived in each device's
/// UserDefaults, which the store still reads when iCloud holds nothing for an area, so
/// an order saved earlier is kept and goes up to iCloud the next time it's changed.
/// Another device's change resets the cache here (`noteExternalChange`) and is
/// announced by `remoteSequenceOrderChanges()` for the screens to reload.
enum FilterOrderStore {

    /// Every area's sub-area order is stored under this prefix plus the area's name.
    nonisolated static let sequenceOrderKeyPrefix = "Lessons.SequenceOrder."
    private static let groupOrderPrefix = sequenceOrderKeyPrefix

    private static var cachedSequenceOrders: [String: [String]] = [:]

    /// Moves on whenever a saved order may have changed, so a result built from
    /// the saved orders (the Lessons map's layout) knows to build again.
    private(set) static var revision = 0

    private static func normalized(_ s: String) -> String {
        s.normalizedForComparison()
    }

    // MARK: Areas

    // The caches below hold the *saved* order, never the merged result. Merging drops
    // whatever the caller didn't pass in `existing`, so caching the result let one
    // narrowed call — the Checklist while its filter field is in use, the map under a
    // chip filter — throw away the saved position of everything absent at that moment.
    // Both screens then read that shortened list back and re-appended the missing
    // names alphabetically, and the order stayed wrong for the rest of the launch.

    /// The areas in the caller's order, each spelling once. Nothing ever
    /// saved an area order, so there is no saved one to read; the merge still
    /// collapses two spellings of one area.
    static func loadAreaOrder(existing: [String]) -> [String] {
        mergeOrder(saved: [], existing: existing)
    }

    // MARK: Groups (Tracks)

    static func loadSequenceOrder(for area: String, existing: [String]) -> [String] {
        let key = groupOrderPrefix + normalized(area)
        if let cached = cachedSequenceOrders[key] {
            return mergeOrder(saved: cached, existing: existing)
        }
        let saved = SyncedPreferencesStore.shared.get(key: key) as? [String] ?? []
        cachedSequenceOrders[key] = saved
        return mergeOrder(saved: saved, existing: existing)
    }

    static func saveSequenceOrder(_ order: [String], for area: String) {
        let key = groupOrderPrefix + normalized(area)
        cachedSequenceOrders[key] = order
        SyncedPreferencesStore.shared.set(order as Any?, forKey: key)
        revision += 1
    }

    // MARK: Cache control

    /// Whether `key` holds an area's sub-area order.
    nonisolated static func isSequenceOrderKey(_ key: String) -> Bool {
        key.hasPrefix(sequenceOrderKeyPrefix)
    }

    /// Another device changed an area's sub-area order, settled for a moment so a burst
    /// of moves reloads once. The cache is already reset when this fires.
    static func remoteSequenceOrderChanges() -> some Publisher<Void, Never> {
        NotificationCenter.default.publisher(for: .syncedPreferencesDidChange)
            // @Sendable: filter closures run on the posting thread.
            .filter { @Sendable note in
                let changed = note.userInfo?["changedKeys"] as? [String] ?? []
                return changed.contains(where: isSequenceOrderKey)
            }
            .map { @Sendable _ in () }
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
    }

    /// Called by `SyncedPreferencesStore` when iCloud brings in another device's
    /// preferences: drops the cached orders those keys may have changed. Nil keys
    /// (a first download or an account change) mean any of them may have.
    static func noteExternalChange(changedKeys: [String]?) {
        guard changedKeys?.contains(where: isSequenceOrderKey) ?? true else { return }
        resetCache()
    }

    static func resetCache() {
        cachedSequenceOrders.removeAll()
        revision += 1
    }

    // MARK: Partial reorder

    /// Rewrites `saved` so the names in `visibleOrder` read in that order, each landing
    /// in a slot one of them already held. Names absent from `visibleOrder` keep their
    /// positions untouched.
    ///
    /// This is what lets a screen showing a filtered subset reorder what it can see
    /// without speaking for what it can't: saving the short list wholesale would drop
    /// every hidden name's stored position and re-append it alphabetically on the next
    /// read. Returns nil when the two lists don't line up — a stale `visibleOrder`
    /// naming something `saved` no longer has, or naming it twice.
    static func applyingVisibleOrder(_ visibleOrder: [String], to saved: [String]) -> [String]? {
        guard visibleOrder.count > 1 else { return nil }
        let visibleKeys = Set(visibleOrder.map(normalized))
        guard visibleKeys.count == visibleOrder.count else { return nil }

        let slots = saved.indices.filter { visibleKeys.contains(normalized(saved[$0])) }
        guard slots.count == visibleOrder.count else { return nil }

        var result = saved
        for (slot, name) in zip(slots, visibleOrder) {
            result[slot] = name
        }
        return result
    }

    // MARK: Merge helper

    /// The saved order, narrowed to what the caller actually has, with anything the
    /// saved order doesn't mention appended in the caller's own order.
    ///
    /// Names are matched normalized rather than by exact string. A sub-area saved as
    /// "Equivalence" and shown as "equivalence" is one sub-area, and matching it
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
