import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Pins what `StudentProgressTabViewModel.loadData` materialises for one
/// student. Each fetch is scoped to the student or to one sequence's lessons,
/// so a classroom's worth of other students' rows never leaves the store.
/// Since 2026-11-03 the cards are the child's standings on the sequences she
/// is in the middle of, read from her presentation rows; nothing is stored.
@Suite("Student Progress Tab load scope")
@MainActor
struct StudentProgressTabLoadScopeTests {

    enum Store {
        case inMemory, sqlite
    }

    private struct Seeded {
        let context: NSManagedObjectContext
        let owner: AnyObject?
        let student: CDStudent
        let firstLesson: CDLesson
        let secondLesson: CDLesson
        let report: CDWorkModel
    }

    /// One student in the middle of Math — Chains (two lessons, the first
    /// mastered and presented), with one note on that lesson, one open report
    /// and one project, next to `others` classmates who each carry the same
    /// shape of data on sequences of their own.
    private func seed(others: Int, store: Store = .inMemory) throws -> Seeded {
        let context: NSManagedObjectContext
        let owner: AnyObject?
        switch store {
        case .inMemory:
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            context = stack.viewContext
            owner = stack
        case .sqlite:
            context = try CoreDataTestHelpers.makeSplitStoreContext()
            owner = nil
        }

        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let studentID = try #require(student.id).uuidString
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains", area: "Math", sequence: "Chains")
        first.orderInSequence = 0
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Squares", area: "Math", sequence: "Chains")
        second.orderInSequence = 1

        seedChains(for: student, lessons: [first, second], in: context)

        let note = CoreDataTestHelpers.seedNote(in: context, body: "Working steadily on chains")
        note.lesson = first
        note.scope = .students([try #require(student.id)])
        note.syncStudentLinks(in: context)

        let studentUUIDForWork = try #require(student.id)
        let secondUUIDForWork = try #require(second.id)
        let report = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "", studentID: studentUUIDForWork, lessonID: secondUUIDForWork
        )
        report.kind = .report

        let project = CDProject(context: context)
        project.title = "Bridges"
        project.memberStudentIDsArray = [studentID]

        seedClassmates(others, in: context)

        let studentUUID = try #require(student.id)
        let firstUUID = try #require(first.id)
        let secondUUID = try #require(second.id)
        let reportUUID = try #require(report.id)
        try context.save()
        context.reset()

        let reloadedStudent = try #require(context.object(CDStudent.self, id: studentUUID))
        let reloadedFirst = try #require(context.object(CDLesson.self, id: firstUUID))
        let reloadedSecond = try #require(context.object(CDLesson.self, id: secondUUID))
        let reloadedReport = try #require(context.object(CDWorkModel.self, id: reportUUID))
        return Seeded(
            context: context, owner: owner, student: reloadedStudent,
            firstLesson: reloadedFirst, secondLesson: reloadedSecond, report: reloadedReport
        )
    }

    /// The student's standing on "Math — Chains": the first lesson mastered
    /// and presented.
    private func seedChains(for student: CDStudent, lessons: [CDLesson], in context: NSManagedObjectContext) {
        let studentID = student.id?.uuidString ?? ""
        let first = lessons[0]

        let mark = CDLessonPresentation(context: context)
        mark.studentID = studentID
        mark.lessonID = first.id?.uuidString ?? ""
        mark.state = .proficient
        mark.presentedAt = Date()

        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = first.id?.uuidString ?? ""
        assignment.studentIDs = [studentID]
        assignment.state = .presented
        assignment.presentedAt = Date()
    }

    /// `count` classmates, each in the middle of a sequence of their own with
    /// a mark, an assignment, a lesson note, a report and a project.
    private func seedClassmates(_ count: Int, in context: NSManagedObjectContext) {
        for index in 0..<count {
            let other = CoreDataTestHelpers.seedStudent(in: context, firstName: "Other", lastName: "\(index)")
            let otherID = other.id?.uuidString ?? ""
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Lesson \(index)", area: "Language", sequence: "Seq \(index)"
            )
            let otherMark = CDLessonPresentation(context: context)
            otherMark.studentID = otherID
            otherMark.lessonID = lesson.id?.uuidString ?? ""
            let otherAssignment = CDLessonAssignment(context: context)
            otherAssignment.lessonID = lesson.id?.uuidString ?? ""
            otherAssignment.studentIDs = [otherID]
            otherAssignment.state = .presented
            let otherNote = CoreDataTestHelpers.seedNote(in: context, body: "Other \(index)")
            otherNote.lesson = lesson
            if let id = other.id {
                otherNote.scope = .students([id])
                otherNote.syncStudentLinks(in: context)
            }
            let otherWork = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Work \(index)", studentID: other.id ?? UUID(), lessonID: lesson.id ?? UUID()
            )
            otherWork.kind = .report
            let otherProject = CDProject(context: context)
            otherProject.title = "Project \(index)"
            otherProject.memberStudentIDsArray = [otherID]
        }
    }

    @Test(
        "The student's standings, stats, report and project are found among classmates",
        arguments: [Store.inMemory, .sqlite]
    )
    func outputsAreScopedToTheStudent(store: Store) throws {
        let seeded = try seed(others: 12, store: store)
        defer { withExtendedLifetime(seeded.owner) {} }
        let viewModel = StudentProgressTabViewModel()
        viewModel.configure(for: seeded.student, context: seeded.context)

        #expect(viewModel.standings.map(\.title) == ["Math — Chains"])
        #expect(viewModel.activeProjects.map(\.title) == ["Bridges"])
        #expect(viewModel.activeReports.map(\.objectID) == [seeded.report.objectID])
        #expect(viewModel.reportTitle(for: seeded.report) == "Bead Squares")

        let standing = try #require(viewModel.standings.first)
        #expect(standing.total == 2)
        #expect(standing.masteredCount == 1)
        #expect(standing.nextLesson?.objectID == seeded.secondLesson.objectID)
        // Her open report on Bead Squares means she's working on it, so the card names
        // no next lesson, as her timeline marks none (bug hunt 2026-11-03 #29).
        #expect(viewModel.nextLessonByStanding[standing.id] == nil)
        #expect(standing.isInProgress)
        #expect(!standing.isFinished)

        let stats = viewModel.stats(for: standing)
        #expect(stats.presentationCount == 1)
        #expect(stats.workCount == 1)
        #expect(stats.noteCount == 1)
        #expect(stats.totalActivity == 3)
    }

    @Test("Loading one student materialises that student's rows, not the classroom's")
    func loadMaterialisesOnlyTheStudentsRows() throws {
        let seeded = try seed(others: 12)
        let before = seeded.context.registeredObjects.count
        let viewModel = StudentProgressTabViewModel()
        viewModel.configure(for: seeded.student, context: seeded.context)
        let registered = seeded.context.registeredObjects.count - before
        // Her mark, the two Chains lessons (first found by her mark, then
        // both by the sequence), her presented assignment, her note and its
        // student link, her report, plus every active project (the roster is
        // a Transformable blob, so projects cannot be scoped in the store):
        // about 20 here. The whole-table load registered 114 (2026-09-18).
        #expect(registered <= 24, "registered \(registered) objects for one student")
    }
}
