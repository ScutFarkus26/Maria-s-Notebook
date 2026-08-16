import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Lessons & Work Navigation")
@MainActor
struct LessonsAndWorkNavigationTests {
    @Test("Every workspace lens can replace every other lens")
    func everyScopeRemainsSelectable() throws {
        let router = AppRouter()

        for first in LessonsAndWorkScope.allCases {
            router.navigateToLessonsAndWork(first)
            #expect(router.selectedNavItem == .planningAgenda)
            #expect(try #require(router.consumeLessonsAndWorkRequest()).scope == first)
            #expect(router.consumeLessonsAndWorkRequest() == nil)

            for second in LessonsAndWorkScope.allCases {
                router.navigateToLessonsAndWork(second)
                #expect(router.selectedNavItem == .planningAgenda)
                #expect(try #require(router.consumeLessonsAndWorkRequest()).scope == second)
            }
        }
    }

    @Test("A route carries the exact record to reveal and is consumed once")
    func focusRequestIsOneShot() throws {
        let router = AppRouter()
        let presentationID = UUID()
        let workID = UUID()

        router.navigateToLessonsAndWork(
            .needsAttention,
            presentationID: presentationID,
            workID: workID
        )

        let request = try #require(router.consumeLessonsAndWorkRequest())
        #expect(request.scope == .needsAttention)
        #expect(request.presentationID == presentationID)
        #expect(request.workID == workID)
        #expect(router.consumeLessonsAndWorkRequest() == nil)
    }

    @Test("The former presentation follow-up route opens Needs Attention")
    func legacyFollowUpRouteUsesUnifiedWorkspace() throws {
        let router = AppRouter()

        router.navigateToPresentationFollowUps()

        #expect(router.selectedNavItem == .planningAgenda)
        #expect(try #require(router.consumeLessonsAndWorkRequest()).scope == .needsAttention)
        #expect(router.selectedNavItem != .lessons)
    }

    @Test("Legacy presentation and work destinations choose the matching lens")
    func legacyRootDestinationsAreCanonicalized() throws {
        let router = AppRouter()

        router.navigateTo(.planningAgenda)
        #expect(router.selectedNavItem == .planningAgenda)
        #expect(try #require(router.consumeLessonsAndWorkRequest()).scope == .upcoming)

        router.navigateTo(.planningWork)
        #expect(router.selectedNavItem == .planningAgenda)
        #expect(try #require(router.consumeLessonsAndWorkRequest()).scope == .childrenWorking)
    }

    @Test("An unknown saved lens falls back to Needs Attention")
    func invalidScopeFallsBackSafely() {
        #expect(LessonsAndWorkScope.resolved(rawValue: "unknown") == .needsAttention)
        #expect(LessonsAndWorkScope.resolved(rawValue: nil) == .needsAttention)
    }

    @Test("Upcoming reveals ready and scheduled assignments in the matching subview")
    func upcomingFocusChoosesMatchingSubview() {
        #expect(
            PresentationsCompactTab.focusedAssignmentDestination(
                isPresented: false,
                scheduledFor: nil
            ) == .ready
        )
        #expect(
            PresentationsCompactTab.focusedAssignmentDestination(
                isPresented: false,
                scheduledFor: Date()
            ) == .week
        )
        #expect(
            PresentationsCompactTab.focusedAssignmentDestination(
                isPresented: true,
                scheduledFor: Date()
            ) == nil
        )
    }

    @Test(
        "Closing a presentation reveals the next guide responsibility",
        arguments: [
            (true, false, LessonsAndWorkScope.needsAttention),
            (true, true, LessonsAndWorkScope.needsAttention),
            (false, true, LessonsAndWorkScope.childrenWorking),
            (false, false, LessonsAndWorkScope.history)
        ]
    )
    func postPresentationDestination(
        hasOpenFollowUp: Bool,
        hasOpenWork: Bool,
        expected: LessonsAndWorkScope
    ) {
        #expect(
            LessonsAndWorkScope.afterPresentation(
                hasOpenFollowUp: hasOpenFollowUp,
                hasOpenWork: hasOpenWork
            ) == expected
        )
    }

    @Test("A focused history record expands pagination to its containing page")
    func focusedHistoryRecordExpandsPagination() {
        let pagination = PaginationState(pageSize: 50)
        pagination.updateTotal(137)

        pagination.revealItem(at: 116)

        #expect(pagination.displayedCount == 137)
        #expect(!pagination.hasMore)
    }

    @Test("Focusing a record already on the first page does not expand history")
    func firstPageFocusDoesNotExpandPagination() {
        let pagination = PaginationState(pageSize: 50)
        pagination.updateTotal(137)

        pagination.revealItem(at: 12)

        #expect(pagination.displayedCount == 50)
        #expect(pagination.hasMore)
    }
}
