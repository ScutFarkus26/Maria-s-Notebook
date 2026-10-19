import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Readiness on the Class Grid's cells (Decisions › Class Grid): Ready is a grey ring;
/// Ready, check first is the grey ring with the amber dot, counted apart ("4 ready ·
/// 1 check first"); and the cell card's Previous lesson box shows what to check.
@Suite("Class Grid readiness marks")
@MainActor
struct ClassGridReadinessMarksTests {

    /// Maya, Eli and Chava; Math › Decimal A then B. Maya and Eli were given A and
    /// confirmed; Maya still has work open on it. Chava has had nothing.
    private struct Fixture {
        let viewModel: ClassAreaChecklistViewModel
        let context: NSManagedObjectContext
        let maya: CDStudent
        let eli: CDStudent
        let chava: CDStudent
        let lessonA: CDLesson
        let lessonB: CDLesson

        func cell(_ student: CDStudent, _ lesson: CDLesson) throws -> CellIdentifier {
            CellIdentifier(studentID: try #require(student.id), lessonID: try #require(lesson.id))
        }

        func state(_ student: CDStudent, _ lesson: CDLesson) throws -> StudentChecklistRowState {
            let studentID = try #require(student.id)
            let lessonID = try #require(lesson.id)
            return try #require(viewModel.matrixStates[studentID]?[lessonID])
        }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Park")
        let chava = CoreDataTestHelpers.seedStudent(in: context, firstName: "Chava", lastName: "Gold")
        let lessonA = CoreDataTestHelpers.seedLesson(in: context, name: "Decimal A", area: "Math", sequence: "Decimal")
        lessonA.orderInSequence = 0
        let lessonB = CoreDataTestHelpers.seedLesson(in: context, name: "Decimal B", area: "Math", sequence: "Decimal")
        lessonB.orderInSequence = 1
        try context.save()

        let given = CDLessonAssignment(context: context)
        given.lessonID = try #require(lessonA.id).uuidString
        given.studentIDs = [maya.cloudKitKey, eli.cloudKitKey]
        given.markPresented(at: try CoreDataTestHelpers.day("2026-09-22"), snapshotLesson: false)
        given.confirmStudent(try #require(maya.id))
        given.confirmStudent(try #require(eli.id))
        _ = try WorkRepository(context: context).createWork(
            studentID: try #require(maya.id), lessonID: try #require(lessonA.id), saveImmediately: false
        )
        try context.save()

        let suite = "ClassGridReadinessMarksTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let viewModel = ClassAreaChecklistViewModel()
        viewModel.collapsedSequencesDefaults = defaults
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return Fixture(
            viewModel: viewModel, context: context, maya: maya, eli: eli, chava: chava,
            lessonA: lessonA, lessonB: lessonB
        )
    }

    @Test("Open work on the lesson before makes Ready, check first, with the reason")
    func openWorkIsCheckFirst() throws {
        let fixture = try makeFixture()
        let maya = try fixture.state(fixture.maya, fixture.lessonB)
        let eli = try fixture.state(fixture.eli, fixture.lessonB)
        let chava = try fixture.state(fixture.chava, fixture.lessonB)

        #expect(maya.displayStatus == .ready)
        #expect(ChecklistCellDescription.checkFirstText(maya) == "1 piece of work still open")
        #expect(eli.displayStatus == .ready)
        #expect(ChecklistCellDescription.checkFirstText(eli) == nil)
        #expect(chava.displayStatus == .notReady)
        #expect(ChecklistCellDescription.checkFirstText(chava) == nil)
    }

    @Test("The Class column and the key count Ready and check first apart")
    func countsApart() throws {
        let fixture = try makeFixture()
        let lessonB = try #require(fixture.lessonB.id)
        let summary = try #require(fixture.viewModel.rowSummaries[lessonB])
        #expect(summary.ready == 2)
        #expect(summary.checkFirst == 1)
        #expect(summary.readyNow == 1)
        #expect(fixture.viewModel.statusCounts.checkFirst == 1)
        // The lens's count and the row's Plan take both.
        #expect(fixture.viewModel.readyCount(for: lessonB) == 2)
        #expect(fixture.viewModel.readyTotal == fixture.viewModel.statusCounts[.ready])
    }

    @Test("A summary counts check first only on Ready cells")
    func summaryFromStates() {
        let lesson = UUID()
        func state(blocking: BlockingReason = .none, reasons: [String] = [], presented: Bool = false)
            -> StudentChecklistRowState {
            StudentChecklistRowState(
                lessonID: lesson, plannedItemID: nil, presentationLogID: nil, contractID: nil,
                isScheduled: false, isPresented: presented, isActive: false, isComplete: false,
                lastActivityDate: nil, isStale: false, blockingReason: blocking, checkFirstReasons: reasons
            )
        }
        let summary = ChecklistRowSummary(states: [
            state(), state(reasons: ["1 piece of work still open"]),
            state(blocking: .confirmationRequired), state(reasons: ["stale"], presented: true), nil
        ])
        #expect(summary.total == 5)
        #expect(summary.ready == 3)
        #expect(summary.checkFirst == 1)
        #expect(summary.readyNow == 2)
        #expect(summary.inProgress == 1)
    }

    @Test("The card's Previous lesson box: when given, open work, last check-in, mastered or not")
    func previousLessonBox() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let cell = try fixture.cell(fixture.maya, fixture.lessonB)

        viewModel.openCard(cell, context: fixture.context)
        let previous = try #require(viewModel.cardPrevious)
        #expect(previous.lessonID == fixture.lessonA.id)
        #expect(previous.name == "Decimal A")
        #expect(previous.status.openWorkCount == 1)
        #expect(previous.status.confirmed)
        #expect(!previous.status.mastered)
        let givenOn = try CoreDataTestHelpers.day("2026-09-22")
        #expect(previous.givenText == "given \(ChecklistCellCardText.shortDate(givenOn))")
        #expect(previous.rows.map(\.value) == ["1", "None yet", "Not yet"])

        // She hasn't had the lesson before: no box.
        viewModel.openCard(try fixture.cell(fixture.chava, fixture.lessonB), context: fixture.context)
        #expect(viewModel.cardPrevious == nil)
        // The first lesson of a sequence has none before it.
        viewModel.openCard(try fixture.cell(fixture.eli, fixture.lessonA), context: fixture.context)
        #expect(viewModel.cardPrevious == nil)
    }

    @Test("The one mark's words: Not yet, and the recall ring")
    func markLabels() {
        #expect(ChecklistMark.label(status: .notReady, recall: nil) == "Not yet")
        #expect(ChecklistMark.label(status: .practicing, recall: nil) == "Practicing")
        #expect(ChecklistMark.label(status: .mastered, recall: .retained) == "Mastered, still has it")
        #expect(ChecklistMark.label(status: .mastered, recall: .shaky) == "Mastered, recall shaky")
        #expect(ChecklistMark.label(status: .reviewing, recall: .forgotten) == "Reviewing, forgotten")
    }

    @Test("The lens reads as the canvas: All marks, Ready with its count")
    func lensTitles() {
        #expect(ChecklistLens.allMarks.title(readyCount: 12) == "All marks")
        #expect(ChecklistLens.ready.title(readyCount: 12) == "Ready 12")
    }
}
