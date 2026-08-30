import Foundation
import Testing
@testable import Maria_s_Notebook

/// Command-click selection, and the multi-record drag it feeds.
///
/// The drag format is the part worth pinning: a selection travels as one item
/// carrying several payloads, and every drop site that predates multi-drag
/// still calls `parse` and has to keep working.
@Suite("Workspace multi-selection")
@MainActor
struct WorkspaceMultiSelectionTests {

    @Test("Toggling adds and removes, and clearing empties")
    func togglingTracksMembership() {
        let selection = WorkspaceMultiSelection()
        let first = UUID()
        let second = UUID()

        #expect(selection.isEmpty)
        selection.toggle(first)
        selection.toggle(second)
        #expect(selection.count == 2)
        #expect(selection.contains(first))

        selection.toggle(first)
        #expect(!selection.contains(first))
        #expect(selection.contains(second))

        selection.clear()
        #expect(selection.isEmpty)
        #expect(!selection.contains(nil))
    }

    @Test("A selection cannot outlive the cards that are on screen")
    func retainDropsWhatIsGone() {
        let selection = WorkspaceMultiSelection()
        let onScreen = UUID()
        let filteredAway = UUID()
        selection.toggle(onScreen)
        selection.toggle(filteredAway)

        selection.retain([onScreen])

        #expect(selection.ids == [onScreen])
    }

    @Test("Dragging an unselected card is still a one-record drag")
    func unselectedCardDragsAlone() {
        let selection = WorkspaceMultiSelection()
        let selected = UUID()
        let dragged = UUID()
        selection.toggle(selected)

        let payload = selection.dragPayload(
            startingAt: dragged,
            make: UnifiedCalendarDragPayload.work
        )

        #expect(UnifiedCalendarDragPayload.parseAll(payload) == [.work(dragged)])
    }

    @Test("Dragging a selected card carries the whole selection, that card first")
    func selectedCardDragsTheSelection() {
        let selection = WorkspaceMultiSelection()
        let dragged = UUID()
        let other = UUID()
        selection.toggle(dragged)
        selection.toggle(other)

        let payload = selection.dragPayload(
            startingAt: dragged,
            make: UnifiedCalendarDragPayload.presentation
        )
        let parsed = UnifiedCalendarDragPayload.parseAll(payload)

        #expect(parsed.count == 2)
        // The card under the pointer leads, so a drop that orders by arrival
        // puts it where the guide aimed it.
        #expect(parsed.first == .presentation(dragged))
        #expect(Set(parsed.map(\.id)) == [dragged, other])
    }

    @Test("A selection of one is indistinguishable from a plain drag")
    func selectionOfOneIsAPlainDrag() {
        let selection = WorkspaceMultiSelection()
        let only = UUID()
        selection.toggle(only)

        let payload = selection.dragPayload(
            startingAt: only,
            make: UnifiedCalendarDragPayload.work
        )

        #expect(payload == UnifiedCalendarDragPayload.work(only).stringRepresentation)
    }

    @Test("A drop site that only knows single drags takes the leading record")
    func legacyDropSiteTakesTheFirstRecord() {
        let first = UUID()
        let second = UUID()
        let payload = UnifiedCalendarDragPayload.joined([.work(first), .work(second)])

        #expect(UnifiedCalendarDragPayload.parse(payload) == .work(first))
    }

    @Test("Single-record strings are unchanged, legacy forms included")
    func singleRecordStringsStillParse() {
        let id = UUID()
        #expect(UnifiedCalendarDragPayload.parse("WORK:\(id.uuidString)") == .work(id))
        #expect(UnifiedCalendarDragPayload.parse("STUDENTLESSON:\(id.uuidString)") == .presentation(id))
        #expect(UnifiedCalendarDragPayload.parse(id.uuidString) == .presentation(id))
        #expect(UnifiedCalendarDragPayload.parse("nonsense") == nil)
        #expect(UnifiedCalendarDragPayload.parseAll("nonsense").isEmpty)
    }
}
