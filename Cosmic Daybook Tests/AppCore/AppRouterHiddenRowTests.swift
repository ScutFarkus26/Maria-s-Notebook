import Foundation
import Testing
@testable import CosmicDaybook

/// `AppRouter.hideRows`: when an empty Classroom row leaves the lists, a
/// window selected on it moves to Today first and only then loses the row,
/// as Apple's note on a `TabView` whose selection is no longer one of its
/// tabs asks (round-two Simplify, Phase 2).
@Suite("Hidden rows move the selection first")
@MainActor
struct AppRouterHiddenRowTests {
    typealias NavigationItem = RootView.NavigationItem

    /// What `hideRows` did, in order.
    private enum Step: Equatable {
        case select(NavigationItem)
        case hide(Set<NavigationItem>)
    }

    private func steps(
        hidden: Set<NavigationItem>, previouslyHidden: Set<NavigationItem>, selection: NavigationItem
    ) -> [Step] {
        var steps: [Step] = []
        AppRouter.hideRows(
            hidden, previouslyHidden: previouslyHidden, selection: selection,
            select: { steps.append(.select($0)) },
            hide: { steps.append(.hide($0)) }
        )
        return steps
    }

    @Test("A selected row that newly hides moves the selection to Today before it goes")
    func newlyHiddenSelectionMovesFirst() {
        #expect(steps(hidden: [.goingOut], previouslyHidden: [], selection: .goingOut)
            == [.select(.today), .hide([.goingOut])])
    }

    @Test("At launch nothing was hidden, so a saved selection on an empty row lands on Today")
    func launchWithSavedSelectionOnEmptyRow() {
        #expect(steps(hidden: [.goingOut, .planningProjects], previouslyHidden: [], selection: .planningProjects)
            == [.select(.today), .hide([.goingOut, .planningProjects])])
    }

    @Test("A retired alias of a hidden row moves too")
    func aliasOfHiddenRowMoves() {
        #expect(steps(hidden: [.planningProjects], previouslyHidden: [], selection: .bookClub)
            == [.select(.today), .hide([.planningProjects])])
    }

    @Test("A row that was already hidden keeps a window opened onto it on purpose")
    func alreadyHiddenRowStays() {
        #expect(steps(hidden: [.goingOut], previouslyHidden: [.goingOut], selection: .goingOut)
            == [.hide([.goingOut])])
    }

    @Test("A selection on a row that stays, or on a tab in the bar, doesn't move")
    func otherSelectionsStay() {
        #expect(steps(hidden: [.goingOut], previouslyHidden: [], selection: .supplies) == [.hide([.goingOut])])
        for tab in RootView.NavigationGroup.primaryTabs {
            #expect(steps(hidden: [.goingOut, .planningProjects], previouslyHidden: [], selection: tab)
                == [.hide([.goingOut, .planningProjects])])
        }
    }

    @Test("Rows coming back move nothing")
    func rowsShowingAgainMoveNothing() {
        #expect(steps(hidden: [], previouslyHidden: [.goingOut], selection: .today) == [.hide([])])
    }
}
