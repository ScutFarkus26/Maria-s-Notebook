import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// A cell click recomputes only the touched lesson's row and the rows that follow it
/// (`ClassAreaChecklistViewModel.refreshRows`). These pin that the result is exactly the
/// matrix a full rebuild gives, for a lesson in the middle of a sequence, so the next
/// lesson's blocking reason really does change under each action.
@Suite("Checklist incremental update")
@MainActor
struct ChecklistIncrementalUpdateTests {

    /// Ada, Bruno and Chava; Math › Decimal lessons 0–3 (default rules: practice and
    /// confirmation both required) and Math › Fractions 0–1. Ada and Bruno share open
    /// work on Decimal 1, so closing it for one changes the other's cell too.
    private struct Fixture {
        let viewModel: ClassAreaChecklistViewModel
        let context: NSManagedObjectContext
        let ada: CDStudent
        let bruno: CDStudent
        let decimal: [CDLesson]
        let fractions: [CDLesson]

        var middle: CDLesson { decimal[1] }
        var next: CDLesson { decimal[2] }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let bruno = CoreDataTestHelpers.seedStudent(in: context, firstName: "Bruno", lastName: "Test")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Chava", lastName: "Test")

        func seedSequence(_ sequence: String, count: Int) -> [CDLesson] {
            (0..<count).map { order in
                let lesson = CoreDataTestHelpers.seedLesson(
                    in: context, name: "\(sequence) \(order)", area: "Math", sequence: sequence
                )
                lesson.orderInSequence = Int64(order)
                return lesson
            }
        }
        let decimal = seedSequence("Decimal", count: 4)
        let fractions = seedSequence("Fractions", count: 2)

        // Both children were shown the first lesson; Ada and Bruno share practice on the second.
        let first = CDLessonAssignment(context: context)
        first.lessonID = try #require(decimal[0].id).uuidString
        first.studentIDs = [ada.cloudKitKey, bruno.cloudKitKey]
        first.markPresented(at: Date(timeIntervalSince1970: 1_780_000_000))

        let work = CDWorkModel(context: context)
        work.lessonID = try #require(decimal[1].id).uuidString
        work.status = .active
        work.createdAt = Date()
        for student in [ada, bruno] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.studentID = student.cloudKitKey
            participant.work = work
        }
        try context.save()

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return Fixture(
            viewModel: viewModel, context: context, ada: ada, bruno: bruno,
            decimal: decimal, fractions: fractions
        )
    }

    private func fullRebuild(_ fixture: Fixture) -> ChecklistMatrixBuilder.Matrix {
        ChecklistMatrixBuilder.buildMatrix(
            students: fixture.viewModel.rosterStudents,
            lessons: fixture.viewModel.lessons,
            context: fixture.context
        )
    }

    private func blocking(_ fixture: Fixture, _ student: CDStudent, _ lesson: CDLesson) throws -> BlockingReason {
        let state = try #require(fixture.viewModel.state(for: student, lesson: lesson))
        return state.blockingReason
    }

    // MARK: - Each Action

    @Test("Presenting a middle lesson matches a full rebuild and unblocks the next one's prerequisite")
    func presentMatchesFullRebuild() throws {
        let fixture = try makeFixture()
        #expect(try blocking(fixture, fixture.ada, fixture.next) == .prerequisiteNotPresented)

        fixture.viewModel.togglePresented(student: fixture.ada, lesson: fixture.middle, context: fixture.context)

        #expect(fixture.viewModel.matrixStates == fullRebuild(fixture))
        #expect(try blocking(fixture, fixture.ada, fixture.next) == .practiceAndConfirmation)
        #expect(fixture.viewModel.state(for: fixture.ada, lesson: fixture.middle)?.isPresented == true)
    }

    @Test("Previously Presented matches a full rebuild")
    func previouslyPresentedMatchesFullRebuild() throws {
        let fixture = try makeFixture()

        fixture.viewModel.togglePreviouslyPresented(
            student: fixture.ada, lesson: fixture.middle, context: fixture.context
        )

        #expect(fixture.viewModel.matrixStates == fullRebuild(fixture))
        #expect(try blocking(fixture, fixture.ada, fixture.next) == .practiceAndConfirmation)
    }

    @Test("Planning a middle lesson matches a full rebuild")
    func planMatchesFullRebuild() throws {
        let fixture = try makeFixture()

        fixture.viewModel.toggleScheduled(student: fixture.ada, lesson: fixture.middle, context: fixture.context)

        #expect(fixture.viewModel.matrixStates == fullRebuild(fixture))
        #expect(fixture.viewModel.state(for: fixture.ada, lesson: fixture.middle)?.isScheduled == true)
        #expect(try blocking(fixture, fixture.ada, fixture.next) == .prerequisiteNotPresented)

        // And taking the plan off again.
        fixture.viewModel.toggleScheduled(student: fixture.ada, lesson: fixture.middle, context: fixture.context)
        #expect(fixture.viewModel.matrixStates == fullRebuild(fixture))
        #expect(fixture.viewModel.state(for: fixture.ada, lesson: fixture.middle)?.isScheduled == false)
    }

    @Test("Mastering a middle lesson matches a full rebuild, including the classmate on the shared work")
    func masterMatchesFullRebuild() throws {
        let fixture = try makeFixture()
        #expect(fixture.viewModel.state(for: fixture.bruno, lesson: fixture.middle)?.isComplete == false)

        fixture.viewModel.markComplete(student: fixture.ada, lesson: fixture.middle, context: fixture.context)

        #expect(fixture.viewModel.matrixStates == fullRebuild(fixture))
        // Presented and practiced; the next lesson now waits only on the guide's confirmation.
        #expect(try blocking(fixture, fixture.ada, fixture.next) == .confirmationRequired)
        #expect(fixture.viewModel.state(for: fixture.ada, lesson: fixture.middle)?.isComplete == true)
        // The shared work closed for Bruno too, and his cell in the touched row shows it.
        #expect(fixture.viewModel.state(for: fixture.bruno, lesson: fixture.middle)?.isComplete == true)
    }

    @Test("Clearing a mastered middle lesson matches a full rebuild and blocks the next one again")
    func clearMatchesFullRebuild() throws {
        let fixture = try makeFixture()
        fixture.viewModel.markComplete(student: fixture.ada, lesson: fixture.middle, context: fixture.context)
        #expect(try blocking(fixture, fixture.ada, fixture.next) == .confirmationRequired)

        fixture.viewModel.clearStatus(student: fixture.ada, lesson: fixture.middle, context: fixture.context)

        #expect(fixture.viewModel.matrixStates == fullRebuild(fixture))
        #expect(try blocking(fixture, fixture.ada, fixture.next) == .prerequisiteNotPresented)
        #expect(fixture.viewModel.state(for: fixture.ada, lesson: fixture.middle)?.isPresented == false)
    }

    @Test("The single entry point routes to the same actions")
    func performRoutesActions() throws {
        let fixture = try makeFixture()
        let cell = CellIdentifier(
            studentID: try #require(fixture.ada.id), lessonID: try #require(fixture.middle.id)
        )

        fixture.viewModel.perform(.togglePresented, on: cell, context: fixture.context)
        #expect(fixture.viewModel.matrixStates == fullRebuild(fixture))
        #expect(fixture.viewModel.state(for: fixture.ada, lesson: fixture.middle)?.isPresented == true)

        fixture.viewModel.perform(.toggleSelection, on: cell, context: fixture.context)
        #expect(fixture.viewModel.selectedCells == [cell])
    }

    // MARK: - Scope

    @Test("Rows the change can't reach are not recomputed")
    func untouchedRowsAreLeftAlone() throws {
        let fixture = try makeFixture()
        // A change behind the grid's back, in another sequence: a full rebuild would show it,
        // a click on Decimal 1 has no reason to look.
        let elsewhere = CDLessonAssignment(context: fixture.context)
        elsewhere.lessonID = try #require(fixture.fractions[1].id).uuidString
        elsewhere.studentIDs = [fixture.ada.cloudKitKey]
        elsewhere.markPresented()
        try fixture.context.save()

        fixture.viewModel.togglePresented(student: fixture.ada, lesson: fixture.middle, context: fixture.context)

        #expect(fixture.viewModel.state(for: fixture.ada, lesson: fixture.fractions[1])?.isPresented == false)
        #expect(fixture.viewModel.state(for: fixture.ada, lesson: fixture.middle)?.isPresented == true)

        // Every row the click could reach still agrees with the full build.
        let full = fullRebuild(fixture)
        let adaID = try #require(fixture.ada.id)
        for lesson in fixture.decimal {
            let lessonID = try #require(lesson.id)
            #expect(fixture.viewModel.matrixStates[adaID]?[lessonID] == full[adaID]?[lessonID])
        }
    }

    @Test("Rebuilding rows over a fresh matrix touches only the lesson and its successor")
    func rebuildRowsWritesOnlyReachableRows() throws {
        let fixture = try makeFixture()
        let students = fixture.viewModel.rosterStudents
        let lessons = fixture.viewModel.lessons
        let middleID = try #require(fixture.middle.id)
        let nextID = try #require(fixture.next.id)

        var matrix: ChecklistMatrixBuilder.Matrix = [:]
        ChecklistMatrixBuilder.rebuildRows(
            in: &matrix, touching: [middleID], students: students, lessons: lessons, context: fixture.context
        )

        let full = fullRebuild(fixture)
        for student in students {
            let studentID = try #require(student.id)
            let row = try #require(matrix[studentID])
            #expect(Set(row.keys) == [middleID, nextID])
            #expect(row[middleID] == full[studentID]?[middleID])
            #expect(row[nextID] == full[studentID]?[nextID])
        }
    }
}
