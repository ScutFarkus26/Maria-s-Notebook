import Foundation
import Testing
@testable import CosmicDaybook

/// The Go menu acts on the window it was chosen in, through that window's
/// own `QuickCaptureActions` and `WindowSectionRequests`, not the shared
/// router that every main window observes.
@Suite("Per-window Go menu")
@MainActor
struct WindowGoMenuTests {
    private final class Calls {
        var names: [String] = []
    }

    @Test("Each window's Go switches reach that window's handlers only")
    func goReachesItsOwnWindow() {
        let calls = Calls()
        func window(_ tag: String) -> QuickCaptureActions {
            let actions = QuickCaptureActions()
            actions.setHandlers(QuickCaptureActions.Handlers(
                newPresentation: {}, newWork: {}, recordPractice: {}, newTodo: {}, newNote: {},
                goTo: { calls.names.append("\(tag).\($0.rawValue)") },
                openLessonsAndWork: { calls.names.append("\(tag).lessonsAndWork.\($0.scope)") }
            ))
            return actions
        }
        let windowA = window("A")
        let windowB = window("B")

        windowB.go(to: .today)
        windowA.go(to: .students)
        windowB.openLessonsAndWork(.init(scope: .attention, preferredKind: .work))

        #expect(calls.names == [
            "B.\(RootView.NavigationItem.today.rawValue)",
            "A.\(RootView.NavigationItem.students.rawValue)",
            "B.lessonsAndWork.\(TriageBucket.attention)"
        ])
    }

    @Test("A lens asked in one window is not seen by another, and leaves the shared router alone")
    func lensStaysInItsWindow() {
        let router = AppRouter()
        let windowA = WindowSectionRequests()
        let windowB = WindowSectionRequests()

        windowB.ask(.init(scope: .attention, preferredKind: .work))

        #expect(windowA.consumeLessonsAndWork() == nil)
        #expect(router.consumeLessonsAndWorkRequest() == nil)
        #expect(router.selectedNavItem == nil)
        let taken = windowB.consumeLessonsAndWork()
        #expect(taken?.scope == .attention)
        #expect(taken?.preferredKind == .work)
    }

    @Test("A lens is taken once")
    func lensTakenOnce() {
        let requests = WindowSectionRequests()
        requests.ask(.init(scope: .toSchedule))

        #expect(requests.consumeLessonsAndWork()?.scope == .toSchedule)
        #expect(requests.lessonsAndWork == nil)
        #expect(requests.consumeLessonsAndWork() == nil)
    }

    @Test("Going to a section routes as the router does: plain sections as they are, Lessons & Work on To Schedule")
    func routesMatchTheRouter() {
        for item: RootView.NavigationItem in [.today, .attendance, .students, .lessons, .notes, .todos] {
            let route = WindowSectionRequests.route(to: item)
            #expect(route.section == item.canonical)
            #expect(route.lessonsAndWork == nil)
        }

        let agenda = WindowSectionRequests.route(to: .planningAgenda)
        #expect(agenda.section == .planningAgenda)
        #expect(agenda.lessonsAndWork?.scope == .toSchedule)
    }
}
