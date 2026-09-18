import Foundation
import Testing
@testable import CosmicDaybook

/// Pins the partial reorder behind hold-to-move on the scope-and-sequence map.
///
/// The map only ever lists the sequences that survived the current chip filters, so a
/// drag speaks for a subset of the area. Writing that subset back as the whole saved
/// order was the bug this guards: every filtered-out sequence lost its stored slot and
/// came back alphabetically at the bottom the next time the map was drawn.
@Suite("Sequence Visible Order")
struct SequenceVisibleOrderTests {

    private let saved = ["Introduction", "Preliminary", "Divisibility", "Fractions", "Algebra"]

    @Test("Reordering everything visible rewrites the whole list")
    func reordersFullList() {
        let moved = ["Preliminary", "Introduction", "Divisibility", "Fractions", "Algebra"]
        #expect(FilterOrderStore.applyingVisibleOrder(moved, to: saved) == moved)
    }

    @Test("Hidden sequences keep the slots they already held")
    func hiddenSequencesKeepTheirSlots() {
        // Only slots 0, 2 and 4 are visible; dragging Algebra to the front rewrites
        // exactly those three, leaving Preliminary at 1 and Fractions at 3.
        let visible = ["Algebra", "Introduction", "Divisibility"]
        #expect(FilterOrderStore.applyingVisibleOrder(visible, to: saved) == [
            "Algebra", "Preliminary", "Introduction", "Fractions", "Divisibility"
        ])
    }

    @Test("Names match the way the store matches them, not literally")
    func matchesNamesNormalized() {
        let visible = ["divisibility", "INTRODUCTION"]
        let result = FilterOrderStore.applyingVisibleOrder(visible, to: saved)
        // The caller's spelling wins in the slot, as it does everywhere else in the store.
        #expect(result == ["divisibility", "Preliminary", "INTRODUCTION", "Fractions", "Algebra"])
    }

    @Test("A list the saved order can't account for is refused")
    func refusesMismatchedLists() {
        #expect(FilterOrderStore.applyingVisibleOrder(["Introduction", "Geometry"], to: saved) == nil)
        #expect(FilterOrderStore.applyingVisibleOrder(["Introduction", "introduction"], to: saved) == nil)
        #expect(FilterOrderStore.applyingVisibleOrder(["Introduction"], to: saved) == nil)
        #expect(FilterOrderStore.applyingVisibleOrder([], to: saved) == nil)
    }
}
