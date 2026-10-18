// Bug hunt 2026-10-17, review (c) of the app shell's classroom switch (#31):
// #1, the question couldn't show over a sheet already up in the window it was
// asked from; #4 and #12, which detail windows count and when they stop; #9, a
// sheet opened while the Sample Class was prepared was lost without asking;
// #10, a presentation already closing still counted; #11a, a test through the
// store's own switch, so leaving the check out of it fails.

import CoreData
import Foundation
import Testing
#if os(iOS)
import UIKit
#endif
@testable import CosmicDaybook

@Suite("Classroom switch through the store (Fix1017ReviewCShell)", .serialized)
@MainActor
struct ClassroomSwitchStoreFix1017ReviewCShellTests {
    /// What the controls' "Switch classroom?" was handed.
    private final class Question {
        var asked = 0
        var proceed: (@MainActor () async -> Void)?

        func ask(_ proceed: @escaping @MainActor () async -> Void) {
            asked += 1
            self.proceed = proceed
        }
    }

    /// A store whose Sample Class lives in `directory`, with `open` as its
    /// "is anything open?" check.
    private func makeStore(in directory: URL, open: @escaping () -> Bool) throws -> ClassroomWorkspaceStore {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        return ClassroomWorkspaceStore(
            primaryStack: stack,
            primaryDependencies: AppDependencies(coreDataStack: stack),
            hasOpenEditors: open,
            sampleStoreURL: directory.appendingPathComponent("sample-classroom.sqlite")
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClassroomSwitchFix1017ReviewCShell-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("While something is open, a switch asks, and changes nothing until Switch")
    func asksWhileOpen() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore(in: directory) { true }
        let question = Question()

        await store.requestSwitch(to: .sampleClass, ask: question.ask)
        #expect(question.asked == 1)
        #expect(store.selection == .myClass)

        let proceed = try #require(question.proceed)
        await proceed()
        #expect(store.selection == .sampleClass)
        // Switch was chosen knowing what was open, so it isn't asked twice.
        #expect(question.asked == 1)

        // A question never answered is a Cancel: nothing changes.
        question.proceed = nil
        await store.requestSwitch(to: .myClass, ask: question.ask)
        #expect(question.asked == 2)
        #expect(store.selection == .sampleClass)
    }

    @Test("With nothing open, a switch happens at once without asking")
    func switchesWhenNothingOpen() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore(in: directory) { false }
        let question = Question()

        await store.requestSwitch(to: .sampleClass, ask: question.ask)
        #expect(store.selection == .sampleClass)
        await store.requestSwitch(to: .myClass, ask: question.ask)
        #expect(store.selection == .myClass)
        #expect(question.asked == 0)
    }

    @Test("Something opened while the Sample Class is prepared is asked about before the switch")
    func asksAboutWhatOpenedWhilePreparing() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Nothing open when Sample Class is chosen; File › New Note… opens
        // while "Preparing Sample Class…" is up.
        var checks = 0
        let store = try makeStore(in: directory) {
            checks += 1
            return checks > 1
        }
        let question = Question()

        await store.requestSwitch(to: .sampleClass, ask: question.ask)
        #expect(question.asked == 1)
        #expect(store.selection == .myClass)
        #expect(!store.isPreparingSample)

        let proceed = try #require(question.proceed)
        await proceed()
        #expect(store.selection == .sampleClass)
    }
}

@Suite("What a classroom switch counts as open (Fix1017ReviewCShell)", .serialized)
@MainActor
struct OpenEditorsFix1017ReviewCShellTests {
    @Test("Only a detail window that holds typing counts as open")
    func onlyEditorWindowsCount() {
        let windows = OpenDetailWindows()
        let student = DetailWindowClassroom(countsAsEditor: false, registry: windows)
        student.hostAppeared(showing: .myClass)
        #expect(!OpenEditorsCheck.anyOpen(detailWindows: windows, sheetUp: false))

        let observation = DetailWindowClassroom(countsAsEditor: true, registry: windows)
        observation.hostAppeared(showing: .myClass)
        #expect(OpenEditorsCheck.anyOpen(detailWindows: windows, sheetUp: false))

        observation.hostDisappeared()
        #expect(!OpenEditorsCheck.anyOpen(detailWindows: windows, sheetUp: false))
    }

    @Test("A detail window stops counting the moment its classroom is switched away, before it has closed")
    func closingWindowStopsCounting() {
        let windows = OpenDetailWindows()
        let observation = DetailWindowClassroom(countsAsEditor: true, registry: windows)
        observation.hostAppeared(showing: .myClass)
        #expect(!observation.isClosing(showing: .myClass))

        observation.classroomChanged(to: .sampleClass)
        #expect(observation.isClosing(showing: .sampleClass))
        #expect(!OpenEditorsCheck.anyOpen(detailWindows: windows, sheetUp: false))

        // Its host showing again (switched back before it closed) counts again.
        observation.classroomChanged(to: .myClass)
        #expect(!observation.isClosing(showing: .myClass))
        observation.hostAppeared(showing: .myClass)
        #expect(OpenEditorsCheck.anyOpen(detailWindows: windows, sheetUp: false))
        observation.hostDisappeared()
    }

    #if os(iOS)
    /// A presentation UIKit is in the middle of closing.
    private final class ClosingController: UIViewController {
        var isClosing = true
        override var isBeingDismissed: Bool { isClosing || super.isBeingDismissed }
    }

    private func makeWindow() throws -> (UIWindow, UIViewController) {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        return (window, root)
    }

    private func dismissAll(from root: UIViewController) async {
        guard root.presentedViewController != nil else { return }
        await withCheckedContinuation { done in
            root.dismiss(animated: false) { done.resume() }
        }
    }

    @Test("A presentation already closing doesn't count as open")
    func closingPresentationDoesntCount() async throws {
        let (window, root) = try makeWindow()
        defer { window.isHidden = true }
        let closing = ClosingController()
        root.present(closing, animated: false)
        try #require(root.presentedViewController === closing)

        #expect(!OpenEditorsCheck.anySheetPresented(in: [window]))
        #expect(ClassroomSwitchQuestion.frontmostPresenter(in: window) === root)

        closing.isClosing = false
        #expect(OpenEditorsCheck.anySheetPresented(in: [window]))
        await dismissAll(from: root)
    }

    @Test("The question is asked over the sheet in front, not under it")
    func asksOverSheet() async throws {
        let (window, root) = try makeWindow()
        defer { window.isHidden = true }
        // A sheet that has finished coming up, as File › New Note…'s has.
        let sheet = UIViewController()
        await withCheckedContinuation { done in
            root.present(sheet, animated: false) { done.resume() }
        }
        try #require(root.presentedViewController === sheet)

        var switched = false
        #expect(ClassroomSwitchQuestion.ask(in: window, animated: false) { switched = true })
        let alert = try #require(sheet.presentedViewController as? UIAlertController)
        #expect(alert.title == "Switch classroom?")
        #expect(alert.message == "What you’re typing in open windows will be lost.")
        #expect(alert.actions.map(\.title) == ["Switch", "Cancel"])
        #expect(alert.actions.map(\.style) == [.destructive, .cancel])
        #expect(!switched)

        // Asking again while it's up doesn't stack a second question.
        #expect(ClassroomSwitchQuestion.ask(in: window, animated: false) { switched = true })
        #expect(alert.presentedViewController == nil)

        await dismissAll(from: root)
    }

    @Test("With nothing in front, the question goes on the window's own screen")
    func asksOnRoot() async throws {
        let (window, root) = try makeWindow()
        defer { window.isHidden = true }

        #expect(ClassroomSwitchQuestion.ask(in: window, animated: false) {})
        #expect(root.presentedViewController is UIAlertController)

        await dismissAll(from: root)
    }
    #endif
}

@Suite("Handoff lands in one window (Fix1017ReviewCShell)")
@MainActor
struct HandoffFix1017ReviewCShellTests {
    private final class Arrivals {
        var destinations: [Handoff.Destination] = []
    }

    private func screen(recordingInto arrivals: Arrivals) -> QuickCaptureActions {
        let actions = QuickCaptureActions()
        actions.setHandlers(QuickCaptureActions.Handlers(
            newPresentation: {},
            newWork: {},
            recordPractice: {},
            newTodo: {},
            newNote: {},
            continueHandoff: { arrivals.destinations.append($0) }
        ))
        return actions
    }

    @Test("A window whose screen is up takes the Handoff itself, not through the router every window watches")
    func windowWithScreenTakesIt() {
        let router = AppRouter()
        let window = WindowHandoff()
        let arrivals = Arrivals()
        // RootView keeps its actions in @State; the window holds them weakly.
        let actions = screen(recordingInto: arrivals)
        window.screenAppeared(actions)

        let lessonID = UUID()
        withExtendedLifetime(actions) {
            window.continueHandoff(to: .lesson(lessonID), router: router)
        }
        #expect(arrivals.destinations == [.lesson(lessonID)])
        #expect(router.selectedNavItem == nil)
        #expect(router.pendingLessonID == nil)
    }

    @Test("Before a window's screen is up, or after it has gone, the router holds the Handoff")
    func routerHoldsItWithoutAScreen() {
        let router = AppRouter()
        let window = WindowHandoff()
        let lessonID = UUID()
        window.continueHandoff(to: .lesson(lessonID), router: router)
        #expect(router.pendingLessonID == lessonID)
        #expect(router.takePendingNavItem() == .lessons)

        // The screen a classroom switch replaced leaving late doesn't unhook
        // the new one; the new one leaving does.
        let arrivals = Arrivals()
        let old = screen(recordingInto: arrivals)
        let new = screen(recordingInto: arrivals)
        window.screenAppeared(old)
        window.screenAppeared(new)
        window.screenDisappeared(old)
        window.continueHandoff(to: .lesson(lessonID), router: router)
        #expect(arrivals.destinations == [.lesson(lessonID)])

        window.screenDisappeared(new)
        _ = router.consumePendingLessonID()
        window.continueHandoff(to: .lesson(lessonID), router: router)
        #expect(arrivals.destinations.count == 1)
        #expect(router.pendingLessonID == lessonID)
    }

    @Test("The window that took it switches section itself; what to open waits in the router for that section")
    func switchesInThatWindow() {
        let router = AppRouter()
        var selected: [RootView.NavigationItem] = []

        let lessonID = UUID()
        router.continueHandoff(to: .lesson(lessonID)) { selected.append($0) }
        #expect(selected == [.lessons])
        #expect(router.selectedNavItem == nil)
        #expect(router.pendingLessonID == lessonID)

        router.continueHandoff(to: .albumPage(albumID: "Biology Album.pdf", pageIndex: 3)) { selected.append($0) }
        #expect(selected == [.lessons, .teachingAlbums])
        #expect(router.selectedNavItem == nil)
        #expect(router.albumPageRequest?.albumID == "Biology Album.pdf")
        #expect(router.albumPageRequest?.pageIndex == 3)

        #if !os(macOS)
        let studentID = UUID()
        router.continueHandoff(to: .student(studentID)) { selected.append($0) }
        #expect(selected == [.lessons, .teachingAlbums, .students])
        #expect(router.selectedNavItem == nil)
        #expect(router.navigationDestination == .openStudentDetail(studentID))
        #endif
    }
}
