// Cosmic Daybook/Lessons/Library/SubAreaOrder.swift

import Foundation

/// The guide's order for one area's sub-areas (sequences), as the Class Grid, the
/// Lessons map and `find_lessons` draw it, and the two ways to change it besides the
/// map's drag: Move Up / Move Down on a Class Grid band, and `reorder_lessons`'
/// `sub_areas` over MCP (2026-11-09).
///
/// The order lives in `FilterOrderStore`, which syncs it between the guide's devices
/// through iCloud key-value storage (`SyncedPreferencesStore`). Lessons filed under no
/// sub-area are one band, which the stored order names "Ungrouped" (the map's and the
/// MCP tools' label) so it keeps the place the guide gave it instead of always
/// trailing the rest.
enum SubAreaOrder {

    /// The stored order's name for the lessons filed under no sub-area.
    static let ungroupedName = "Ungrouped"

    /// `named` (the area's sub-areas, as `LessonsViewModel.groups(for:lessons:)` gives
    /// them) with "" for the unfiled lessons at its stored place, when there are any.
    static func withUngrouped(_ named: [String], hasUngrouped: Bool, area: String) -> [String] {
        guard hasUngrouped else { return named }
        let trimmedArea = area.trimmed()
        guard !trimmedArea.isEmpty else { return named + [""] }
        return FilterOrderStore.loadSequenceOrder(for: trimmedArea, existing: named + [ungroupedName])
            .map { isUngrouped($0) ? "" : $0 }
    }

    /// `full` after `sequence` moves `step` places (-1 up, +1 down) among `visible`,
    /// the bands on screen; any sub-area a filter hides keeps its slot. Nil when
    /// `sequence` is already at that edge, or isn't on screen. "" is the unfiled band.
    static func moving(_ sequence: String, by step: Int, visible: [String], in full: [String]) -> [String]? {
        guard step != 0,
              let from = visible.firstIndex(where: { same($0, sequence) }),
              visible.indices.contains(from + step)
        else { return nil }
        var reordered = visible
        reordered.swapAt(from, from + step)
        return FilterOrderStore.applyingVisibleOrder(
            reordered.map(stored), to: full.map(stored)
        )?.map { isUngrouped($0) ? "" : $0 }
    }

    /// The area's full order after a drag in the Lessons map put the rows on screen
    /// into `visibleOrder`; `named` is the area's sub-areas in their current order.
    /// The map drags only named sub-areas, so the unfiled band's stored place is
    /// carried through here: saving the named ones alone sent it back to the bottom.
    /// Nil when `visibleOrder` doesn't line up with the area (see
    /// `FilterOrderStore.applyingVisibleOrder`).
    static func applying(visibleOrder: [String], toNamed named: [String], area: String) -> [String]? {
        let full = withUngrouped(named, hasUngrouped: true, area: area)
        return FilterOrderStore.applyingVisibleOrder(visibleOrder.map(stored), to: full.map(stored))
    }

    /// Saves `order` (sub-area names, "" or "Ungrouped" for the unfiled band) as the area's order.
    static func save(_ order: [String], area: String) {
        let trimmedArea = area.trimmed()
        guard !trimmedArea.isEmpty else { return }
        FilterOrderStore.saveSequenceOrder(order.map(stored), for: trimmedArea)
    }

    // MARK: - Private

    private static func stored(_ name: String) -> String {
        name.trimmed().isEmpty ? ungroupedName : name
    }

    private static func isUngrouped(_ name: String) -> Bool {
        same(name, ungroupedName)
    }

    private static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.normalizedForComparison() == rhs.normalizedForComparison()
    }
}
