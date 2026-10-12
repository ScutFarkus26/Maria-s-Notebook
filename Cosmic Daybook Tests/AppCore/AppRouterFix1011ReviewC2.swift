import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11, review c #2: File › New Lesson…, New Student…,
/// Import Students… and the sidebar's menus act on the window they were
/// chosen in, through that window's own requests, not the shared router that
/// every window's Lessons and Students observe.
@Suite("Per-window New Lesson and New Student 2026-10-11")
@MainActor
struct AppRouterFix1011ReviewC2 {
    typealias Request = WindowCreateRequests.Request

    private final class Calls {
        var names: [String] = []
    }

    @Test("Each window's New Lesson, New Student and Import Students reach that window's handlers only")
    func quickCaptureReachesItsOwnWindow() {
        let calls = Calls()
        func window(_ tag: String) -> QuickCaptureActions {
            let actions = QuickCaptureActions()
            actions.setHandlers(QuickCaptureActions.Handlers(
                newPresentation: {}, newWork: {}, recordPractice: {}, newTodo: {}, newNote: {},
                newLesson: { calls.names.append("\(tag).newLesson") },
                newStudent: { calls.names.append("\(tag).newStudent") },
                importStudents: { calls.names.append("\(tag).importStudents") }
            ))
            return actions
        }
        let windowA = window("A")
        let windowB = window("B")

        windowB.newLesson()
        windowB.newStudent()
        windowA.importStudents()

        #expect(calls.names == ["B.newLesson", "B.newStudent", "A.importStudents"])
    }

    @Test("A request asked in one window is not seen by another, and leaves the shared router alone")
    func requestStaysInItsWindow() {
        let router = AppRouter()
        let windowA = WindowCreateRequests()
        let windowB = WindowCreateRequests()

        windowB.ask(.newLesson(defaultArea: nil, defaultSequence: nil))

        #expect(windowA.consumeNewLesson() == nil)
        #expect(router.consumeNewLessonRequest() == nil)
        #expect(router.navigationDestination == nil)
        #expect(windowB.consumeNewLesson() == AppRouter.NewLessonRequest(defaultArea: nil, defaultSequence: nil))
    }

    @Test("New Lesson is taken once, with its default area and sequence")
    func newLessonTakenOnce() {
        let requests = WindowCreateRequests()
        requests.ask(.newLesson(defaultArea: "Math", defaultSequence: "Fractions"))

        let expected = AppRouter.NewLessonRequest(defaultArea: "Math", defaultSequence: "Fractions")
        #expect(requests.consumeNewLesson() == expected)
        #expect(requests.pending == nil)
        #expect(requests.consumeNewLesson() == nil)
    }

    @Test("Lessons leaves a Students request for Students, and Students leaves a New Lesson for Lessons")
    func eachScreenTakesOnlyItsOwn() {
        let requests = WindowCreateRequests()
        requests.ask(.importStudents)
        #expect(requests.consumeNewLesson() == nil)
        #expect(requests.pending == .importStudents)
        #expect(requests.consumeStudentRequest() == .importStudents)
        #expect(requests.consumeStudentRequest() == nil)

        requests.ask(.newLesson(defaultArea: nil, defaultSequence: nil))
        #expect(requests.consumeStudentRequest() == nil)
        #expect(requests.pending == .newLesson(defaultArea: nil, defaultSequence: nil))

        requests.ask(.newStudent)
        #expect(requests.consumeStudentRequest() == .newStudent)
    }

    @Test("Each request names the section that shows its sheet")
    func answeringSections() {
        #expect(Request.newLesson(defaultArea: nil, defaultSequence: nil).answeringSection == .lessons)
        #expect(Request.newStudent.answeringSection == .students)
        #expect(Request.importStudents.answeringSection == .students)
    }
}
