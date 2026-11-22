import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Pins the `cosmicdaybook://` address: what it parses, what it refuses, and
/// where each kind opens once it is looked up in the notebook.
@MainActor
@Suite("Notebook links")
struct NotebookLinkTests {

    // MARK: Parsing

    @Test("Each kind's address names it")
    func eachKind() throws {
        let id = UUID()
        let expected: [(String, NotebookLink.Target)] = [
            ("student", .student(id)), ("lesson", .lesson(id)), ("follow-up", .followUp(id))
        ]
        for (host, target) in expected {
            let url = try #require(URL(string: "cosmicdaybook://\(host)/\(id.uuidString)"))
            #expect(NotebookLink.target(from: url) == target)
            #expect(target.host == host)
        }
    }

    @Test("Scheme and kind are matched without regard to case, and a lowercase id parses")
    func caseInsensitive() throws {
        let id = UUID()
        let url = try #require(URL(string: "CosmicDaybook://Student/\(id.uuidString.lowercased())"))
        #expect(NotebookLink.target(from: url) == .student(id))
    }

    @Test("An id that isn't a UUID leads nowhere")
    func badID() throws {
        for text in ["cosmicdaybook://student/not-a-uuid",
                     "cosmicdaybook://lesson/12345",
                     "cosmicdaybook://follow-up/\(UUID().uuidString)x"] {
            let url = try #require(URL(string: text))
            #expect(NotebookLink.target(from: url) == nil, "\(text)")
        }
    }

    @Test("A missing part leads nowhere: no kind, no id, or an empty path")
    func missingPart() throws {
        let id = UUID().uuidString
        for text in ["cosmicdaybook:///\(id)",
                     "cosmicdaybook://student",
                     "cosmicdaybook://student/",
                     "cosmicdaybook:student/\(id)",
                     "cosmicdaybook://"] {
            let url = try #require(URL(string: text))
            #expect(NotebookLink.target(from: url) == nil, "\(text)")
        }
    }

    @Test("Anything past the id leads nowhere: another path part, a query, a fragment, a port or a user")
    func extraParts() throws {
        let id = UUID().uuidString
        for text in ["cosmicdaybook://student/\(id)/edit",
                     "cosmicdaybook://student/\(id)/",
                     "cosmicdaybook://student/\(id)?delete=1",
                     "cosmicdaybook://student/\(id)#notes",
                     "cosmicdaybook://student:8080/\(id)",
                     "cosmicdaybook://someone@student/\(id)"] {
            let url = try #require(URL(string: text))
            #expect(NotebookLink.target(from: url) == nil, "\(text)")
        }
    }

    @Test("An unknown kind leads nowhere")
    func unknownHost() throws {
        let id = UUID().uuidString
        for text in ["cosmicdaybook://work/\(id)", "cosmicdaybook://students/\(id)",
                     "cosmicdaybook://followup/\(id)"] {
            let url = try #require(URL(string: text))
            #expect(NotebookLink.target(from: url) == nil, "\(text)")
        }
    }

    @Test("Another scheme leads nowhere")
    func wrongScheme() throws {
        let id = UUID().uuidString
        for text in ["https://student/\(id)", "tide://student/\(id)", "cosmic-daybook://student/\(id)",
                     "file:///student/\(id)"] {
            let url = try #require(URL(string: text))
            #expect(NotebookLink.target(from: url) == nil, "\(text)")
        }
    }

    @Test("The scheme is declared in CFBundleURLTypes, or the system never sends the app its links")
    func declaredInInfoPlist() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(NotebookLink.scheme))
    }

    // MARK: Looking up

    @Test("A child or a lesson in the notebook opens by the Handoff route")
    func studentAndLesson() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context)
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let studentID = try #require(student.id)
        let lessonID = try #require(lesson.id)

        #expect(NotebookLink.landing(for: .student(studentID), in: context) == .handoff(.student(studentID)))
        #expect(NotebookLink.landing(for: .lesson(lessonID), in: context) == .handoff(.lesson(lessonID)))
    }

    @Test("An id that isn't in the notebook opens nothing, whatever its kind")
    func notInNotebook() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let lessonID = try #require(lesson.id)

        #expect(NotebookLink.landing(for: .student(UUID()), in: context) == nil)
        #expect(NotebookLink.landing(for: .lesson(UUID()), in: context) == nil)
        #expect(NotebookLink.landing(for: .followUp(UUID()), in: context) == nil)
        // A lesson's id is not a child's.
        #expect(NotebookLink.landing(for: .student(lessonID), in: context) == nil)
    }

    @Test("A follow-up opens where it is shown: a goal and a one-child note on the child's page, else Today")
    func followUps() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya")
        let leo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leo")
        let mayaID = try #require(maya.id)
        let leoID = try #require(leo.id)

        let todo = CDTodoItem(context: context)
        todo.title = "Call Maya's father"
        todo.resolvedStudentIDs = [mayaID]

        let goal = CDStudentFocusItem(context: context)
        goal.studentIDUUID = mayaID
        goal.text = "Finish the bead chain"

        let orphanGoal = CDStudentFocusItem(context: context)
        orphanGoal.studentIDUUID = UUID()

        let oneChild = CoreDataTestHelpers.seedNote(in: context)
        oneChild.needsFollowUp = true
        oneChild.scope = .student(leoID)

        let twoChildren = CoreDataTestHelpers.seedNote(in: context)
        twoChildren.needsFollowUp = true
        twoChildren.scope = .students([mayaID, leoID])

        let wholeClass = CoreDataTestHelpers.seedNote(in: context)
        wholeClass.needsFollowUp = true
        wholeClass.scope = .all

        func landing(_ id: UUID?) throws -> NotebookLink.Landing? {
            NotebookLink.landing(for: .followUp(try #require(id)), in: context)
        }
        #expect(try landing(todo.id) == .section(.today))
        #expect(try landing(goal.id) == .handoff(.student(mayaID)))
        #expect(try landing(orphanGoal.id) == .section(.today))
        #expect(try landing(oneChild.id) == .handoff(.student(leoID)))
        #expect(try landing(twoChildren.id) == .section(.today))
        #expect(try landing(wholeClass.id) == .section(.today))
    }

    @Test("A link only looks: opening one saves nothing and changes nothing")
    func readOnly() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context)
        let todo = CDTodoItem(context: context)
        try context.save()

        _ = NotebookLink.landing(for: .student(try #require(student.id)), in: context)
        _ = NotebookLink.landing(for: .followUp(try #require(todo.id)), in: context)
        _ = NotebookLink.landing(for: .lesson(UUID()), in: context)
        #expect(!context.hasChanges)
    }

    // MARK: Waiting for the screen

    @Test("A link that comes before the window's screen is up waits for it, then opens there once")
    func waitsForScreen() {
        let window = WindowHandoff()
        let screen = QuickCaptureActions()
        var opened: [NotebookLink.Target] = []
        screen.setHandlers(QuickCaptureActions.Handlers(
            newPresentation: {}, newWork: {}, recordPractice: {}, newTodo: {}, newNote: {},
            openLink: { opened.append($0) }
        ))
        let first = NotebookLink.Target.lesson(UUID())
        let second = NotebookLink.Target.student(UUID())

        window.openLink(first)
        window.openLink(second)
        #expect(opened.isEmpty)

        window.screenAppeared(screen)
        #expect(opened == [second])

        window.screenAppeared(screen)
        #expect(opened == [second])

        window.openLink(first)
        #expect(opened == [second, first])
    }
}
