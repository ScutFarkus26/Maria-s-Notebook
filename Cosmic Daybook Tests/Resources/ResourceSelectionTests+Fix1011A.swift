import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11 #59: a filter can hide resources selected earlier, and
/// the bulk actions and Select All used to count them. Delete removed
/// worksheets the guide could no longer see.
@Suite("Resources: select mode acts on what's visible (bug hunt 10-11)")
@MainActor
struct ResourceSelectionFix1011ATests {

    private let shown = UUID()
    private let alsoShown = UUID()
    private let hiddenByFilter = UUID()

    @Test("Bulk actions change only the selected resources the filter shows")
    func bulkActionsSkipHiddenSelections() {
        let selection = ResourceSelection(visibleIDs: [shown, alsoShown], selectedIDs: [shown, hiddenByFilter])
        #expect(selection.actedOnIDs == [shown])
    }

    @Test("Select All isn't fooled by a hidden selection that makes the counts match")
    func selectAllComparesTheVisibleResources() {
        let selection = ResourceSelection(visibleIDs: [shown, alsoShown], selectedIDs: [shown, hiddenByFilter])
        #expect(!selection.allVisibleSelected)
        #expect(selection.togglingAll().isSuperset(of: [shown, alsoShown]))
    }

    @Test("Deselect All clears what the filter shows")
    func deselectAllClearsTheVisibleResources() {
        let selection = ResourceSelection(visibleIDs: [shown, alsoShown],
                                          selectedIDs: [shown, alsoShown, hiddenByFilter])
        #expect(selection.allVisibleSelected)
        #expect(selection.togglingAll().isDisjoint(with: [shown, alsoShown]))
    }
}
