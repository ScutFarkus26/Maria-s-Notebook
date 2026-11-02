import Foundation
import Testing
@testable import CosmicDaybook

/// Command-click selection, and the drag strings the Year Plan and the
/// Consolidate sheet still read with `parse`.
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

    @Test("Single-record strings are unchanged, a bare id included")
    func singleRecordStringsStillParse() {
        let id = UUID()
        #expect(UnifiedCalendarDragPayload.parse("WORK:\(id.uuidString)") == .work(id))
        #expect(UnifiedCalendarDragPayload.parse("CHECKIN:\(id.uuidString)") == nil)
        #expect(UnifiedCalendarDragPayload.parse(id.uuidString) == .presentation(id))
        #expect(UnifiedCalendarDragPayload.parse("nonsense") == nil)
        // A string carrying several records reads as the first of them.
        let second = UUID()
        #expect(UnifiedCalendarDragPayload.parse("WORK:\(id.uuidString)\nWORK:\(second.uuidString)") == .work(id))
    }
}
