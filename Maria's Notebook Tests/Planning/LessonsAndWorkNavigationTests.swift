import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Lessons & Work Navigation")
@MainActor
struct LessonsAndWorkNavigationTests {
    @Test("Every workspace lens can replace every other lens")
    func everyScopeRemainsSelectable() throws {
        let router = AppRouter()

        for first in TriageBucket.workspaceCases {
            router.navigateToLessonsAndWork(first)
            #expect(router.selectedNavItem == .planningAgenda)
            #expect(try #require(router.consumeLessonsAndWorkRequest()).scope == first)
            #expect(router.consumeLessonsAndWorkRequest() == nil)

            for second in TriageBucket.workspaceCases {
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
            .attention,
            presentationID: presentationID,
            workID: workID
        )

        let request = try #require(router.consumeLessonsAndWorkRequest())
        #expect(request.scope == .attention)
        #expect(request.presentationID == presentationID)
        #expect(request.workID == workID)
        #expect(router.consumeLessonsAndWorkRequest() == nil)
    }

    @Test("The former presentation follow-up route opens Needs Attention")
    func legacyFollowUpRouteUsesUnifiedWorkspace() throws {
        let router = AppRouter()

        router.navigateToPresentationFollowUps()

        #expect(router.selectedNavItem == .planningAgenda)
        #expect(try #require(router.consumeLessonsAndWorkRequest()).scope == .attention)
        #expect(router.selectedNavItem != .lessons)
    }

    @Test("The planning destination opens the workspace on the upcoming lens")
    func planningDestinationChoosesUpcoming() throws {
        let router = AppRouter()

        router.navigateTo(.planningAgenda)
        #expect(router.selectedNavItem == .planningAgenda)
        #expect(try #require(router.consumeLessonsAndWorkRequest()).scope == .toSchedule)
    }

    @Test("An unknown saved lens falls back to Needs Attention")
    func invalidScopeFallsBackSafely() {
        #expect(TriageBucket.resolved(rawValue: "unknown") == .attention)
        #expect(TriageBucket.resolved(rawValue: nil) == .attention)
        // `.done` is a real bucket but not a workspace list, so a saved value
        // naming it must not select a tab that cannot render.
        #expect(TriageBucket.resolved(rawValue: TriageBucket.done.rawValue) == .attention)
    }

    @Test("The Ready list only claims a presentation it can actually show")
    func readyListClaimsOnlyUnscheduled() {
        // Unscheduled and not yet given is exactly what the Ready list holds.
        #expect(
            PresentationsView.canRevealInReadyList(isPresented: false, scheduledFor: nil)
        )
        // A scheduled one belongs to the Scheduled calendar pinned below.
        #expect(
            !PresentationsView.canRevealInReadyList(isPresented: false, scheduledFor: Date())
        )
        // A given one is history, and history lives under Logs.
        #expect(
            !PresentationsView.canRevealInReadyList(isPresented: true, scheduledFor: Date())
        )
    }

    @Test(
        "Closing a presentation reveals the next guide responsibility",
        arguments: [
            (true, false, TriageBucket.attention),
            (true, true, TriageBucket.attention),
            (false, true, TriageBucket.toSchedule),
            (false, false, TriageBucket.attention)
        ]
    )
    func postPresentationDestination(
        hasOpenFollowUp: Bool,
        hasOpenWork: Bool,
        expected: TriageBucket
    ) {
        #expect(
            TriageBucket.afterPresentation(
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
