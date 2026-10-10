import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The checklist's Mastered and Clear (bug hunt 2026-10-10, #41 and #42): Mastered
/// gates on the mastery mark and reuses closed work instead of adding a row; Clear
/// means the same from a cell and from the selection bar, leaves the cell blank,
/// and keeps the notes written on work it removes.
@Suite("Checklist Mastered and Clear (fix 10-10 H)")
@MainActor
struct ChecklistMasteredClearFix1010HTests {

    private struct Fixture {
        let viewModel: ClassAreaChecklistViewModel
        let context: NSManagedObjectContext
        let ada: CDStudent
        let bruno: CDStudent
        let lesson: CDLesson

        func status(_ student: CDStudent) -> ChecklistDisplayStatus? {
            viewModel.state(for: student, lesson: lesson)?.displayStatus
        }

        func cell(_ student: CDStudent) -> CellIdentifier {
            CellIdentifier(studentID: student.id!, lessonID: lesson.id!)
        }

        func works(_ student: CDStudent) -> [CDWorkModel] {
            let request = CDFetchRequest(CDWorkModel.self)
            request.predicate = NSPredicate(format: "lessonID == %@", lesson.id!.uuidString)
            return context.safeFetch(request).filter { WorkGrouping.involves(student.id!, in: $0) }
        }

        func history(_ student: CDStudent) -> [CDLessonPresentation] {
            let request = CDFetchRequest(CDLessonPresentation.self)
            request.predicate = NSPredicate(
                format: "studentID == %@ AND lessonID == %@", student.id!.uuidString, lesson.id!.uuidString
            )
            return context.safeFetch(request)
        }

        func work(for student: CDStudent, status: WorkStatus) throws -> CDWorkModel {
            let row = try WorkRepository(context: context).createWork(
                studentID: student.id!, lessonID: lesson.id!, saveImmediately: false
            )
            if status != .active {
                try WorkLogService.log([.init(work: row, status: status)], context: context, saveImmediately: false)
            }
            return row
        }

        /// Given today, with closed (Keep Practicing) work carrying a note: a Reviewing cell.
        func reviewingCell(for student: CDStudent) throws -> (work: CDWorkModel, note: CDNote) {
            _ = PresentationFactory.makePresented(lessonID: lesson.id!, studentIDs: [student.id!], context: context)
            let row = try self.work(for: student, status: .keepPracticing)
            let note = CoreDataTestHelpers.seedNote(in: context, body: "Needs the bank game again")
            note.work = row
            try context.save()
            viewModel.recomputeMatrix(context: context)
            return (row, note)
        }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let bruno = CoreDataTestHelpers.seedStudent(in: context, firstName: "Bruno", lastName: "Test")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Decimal 0", area: "Math", sequence: "Decimal")
        try context.save()

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return Fixture(viewModel: viewModel, context: context, ada: ada, bruno: bruno, lesson: lesson)
    }

    @Test("Mastered from the selection bar marks a Reviewing cell")
    func batchMasteredMarksReviewing() throws {
        let fixture = try makeFixture()
        _ = try fixture.reviewingCell(for: fixture.ada)
        #expect(fixture.status(fixture.ada) == .reviewing)

        fixture.viewModel.selectedCells = [fixture.cell(fixture.ada)]
        fixture.viewModel.batchMarkProficient(context: fixture.context)

        #expect(fixture.status(fixture.ada) == .mastered)
        #expect(fixture.works(fixture.ada).count == 1)
    }

    @Test("Mastered on a cell with closed work keeps that row and its verdict")
    func cellMasteredReusesClosedWork() throws {
        let fixture = try makeFixture()
        let (closed, _) = try fixture.reviewingCell(for: fixture.ada)

        fixture.viewModel.markComplete(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)

        #expect(fixture.works(fixture.ada).map(\.objectID) == [closed.objectID])
        #expect(closed.status == .keepPracticing)
        #expect(fixture.status(fixture.ada) == .mastered)
    }

    @Test("Mastered closes the child's open work rather than adding a row")
    func masteredClosesOpenWork() throws {
        let fixture = try makeFixture()
        let open = try fixture.work(for: fixture.ada, status: .active)
        try fixture.context.save()

        fixture.viewModel.selectedCells = [fixture.cell(fixture.ada)]
        fixture.viewModel.batchMarkProficient(context: fixture.context)

        #expect(fixture.works(fixture.ada).map(\.objectID) == [open.objectID])
        #expect(open.status.isClosed)
        #expect(!fixture.context.hasChanges)
    }

    @Test("Clear on a cell and from the selection bar leave the same blank cell, and keep the notes")
    func clearIsOneRule() throws {
        let fixture = try makeFixture()
        let ada = try fixture.reviewingCell(for: fixture.ada)
        let bruno = try fixture.reviewingCell(for: fixture.bruno)
        fixture.viewModel.markComplete(student: fixture.bruno, lesson: fixture.lesson, context: fixture.context)

        fixture.viewModel.clearStatus(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)
        fixture.viewModel.selectedCells = [fixture.cell(fixture.bruno)]
        fixture.viewModel.batchClearStatus(context: fixture.context)

        for (student, records) in [(fixture.ada, ada), (fixture.bruno, bruno)] {
            #expect(fixture.status(student) == .ready)
            #expect(fixture.works(student).isEmpty)
            #expect(fixture.history(student).isEmpty)
            #expect(!records.note.isDeleted && records.note.managedObjectContext != nil)
            #expect(records.note.work == nil)
            #expect(records.note.body == "Needs the bank game again")
            // A work row's note is class-wide; kept as is it would show on every child's page.
            #expect(records.note.scope == .student(student.id!))
            #expect(!records.note.scopeIsAll)
            #expect(records.note.lessonID == fixture.lesson.id!.uuidString)
        }
        #expect(!fixture.context.hasChanges)
    }

    @Test("Clear keeps the notes on a presentation she had alone, and her history's text")
    func clearKeepsPresentationNotesAndHistoryText() throws {
        let fixture = try makeFixture()
        let ada = fixture.ada.id!
        let given = PresentationFactory.makePresented(
            lessonID: fixture.lesson.id!, studentIDs: [ada], context: fixture.context
        )
        let observation = CoreDataTestHelpers.seedNote(in: fixture.context, body: "Counted every bead")
        observation.scope = .student(ada)
        observation.lessonAssignment = given
        let row = CDLessonPresentation(context: fixture.context)
        row.studentID = ada.uuidString
        row.lessonID = fixture.lesson.id!.uuidString
        row.presentationID = given.id?.uuidString
        row.notes = "Explained it to Bruno"
        row.followUpNote = "Try the bank game next"
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.clearStatus(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)

        #expect(given.isDeleted || given.managedObjectContext == nil)
        #expect(!observation.isDeleted && observation.managedObjectContext != nil)
        #expect(observation.lessonAssignment == nil)
        #expect(observation.scope == .student(ada))
        let kept = fixture.context.safeFetch(CDFetchRequest(CDNote.self))
            .filter { $0.body.contains("Explained it to Bruno") }
        #expect(kept.count == 1)
        #expect(kept.first?.body.contains("Try the bank game next") == true)
        #expect(kept.first?.scope == .student(ada))
        #expect(kept.first?.lessonID == fixture.lesson.id!.uuidString)
        #expect(fixture.status(fixture.ada) == .ready)
    }

    @Test("Clear asks first when a cell holds history, and clears plans straight away")
    func clearAsksFirstForHistory() throws {
        let fixture = try makeFixture()
        // Bruno: only a plan, so his cell clears at once.
        _ = PresentationFactory.makeDraft(
            lessonID: fixture.lesson.id!, studentIDs: [fixture.bruno.id!], context: fixture.context
        )
        // Ada: given, mastered, finished work.
        _ = try fixture.reviewingCell(for: fixture.ada)
        fixture.viewModel.markComplete(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.perform(.clearStatus, on: fixture.cell(fixture.bruno), context: fixture.context)
        #expect(fixture.viewModel.pendingClear == nil)
        #expect(fixture.status(fixture.bruno) == .ready)

        fixture.viewModel.perform(.clearStatus, on: fixture.cell(fixture.ada), context: fixture.context)
        let request = try #require(fixture.viewModel.pendingClear)
        #expect(request.summary == ChecklistClearSummary(
            cells: 1, givenPresentations: 1, masteryMarks: 1, finishedWork: 1
        ))
        #expect(request.message.contains("1 given presentation, 1 mastery mark, and 1 finished work item"))
        #expect(request.message.hasSuffix("This can't be undone."))
        #expect(fixture.status(fixture.ada) == .mastered)

        fixture.viewModel.cancelClear()
        #expect(fixture.status(fixture.ada) == .mastered)

        fixture.viewModel.selectedCells = [fixture.cell(fixture.ada)]
        fixture.viewModel.requestBatchClear(context: fixture.context)
        let batch = try #require(fixture.viewModel.pendingClear)
        #expect(batch.fromSelection)
        fixture.viewModel.confirmClear(batch, context: fixture.context)

        #expect(fixture.viewModel.pendingClear == nil)
        #expect(fixture.status(fixture.ada) == .ready)
        #expect(fixture.viewModel.selectedCells.isEmpty)
    }

    @Test("Clear takes a child off a shared row and leaves it for the others")
    func clearKeepsSharedWork() throws {
        let fixture = try makeFixture()
        let shared = try fixture.work(for: fixture.ada, status: .active)
        let participant = CDWorkParticipantEntity(context: fixture.context)
        participant.studentID = fixture.bruno.id!.uuidString
        participant.work = shared
        try fixture.context.save()

        fixture.viewModel.clearStatus(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)

        #expect(!shared.isDeleted && shared.managedObjectContext != nil)
        #expect(!WorkGrouping.involves(fixture.ada.id!, in: shared))
        #expect(WorkGrouping.involves(fixture.bruno.id!, in: shared))
    }
}
