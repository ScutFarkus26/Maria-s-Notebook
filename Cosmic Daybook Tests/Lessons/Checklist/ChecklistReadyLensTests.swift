import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The Ready to Present lens (plan, Phase 5): which children a lesson is Ready for — not
/// presented, not planned, nothing before it holding her back — read through the view
/// model over a store, and the row's Plan, a draft for exactly those children.
@Suite("Checklist Ready lens")
@MainActor
struct ChecklistReadyLensTests {

    /// Ada, Bruno, Chava. Math › Decimal at orders 0, 1, 2 and 7 (a gap in the numbering;
    /// no sequence settings, so practice and confirmation are both required), and
    /// Math › Geometry 0–1, whose settings ask for the guide's confirmation only.
    private struct Fixture {
        let viewModel: ClassAreaChecklistViewModel
        let context: NSManagedObjectContext
        let ada: CDStudent
        let bruno: CDStudent
        let chava: CDStudent
        let decimal: [CDLesson]
        let geometry: [CDLesson]

        var studentOrder: [UUID] { viewModel.students.compactMap(\.id) }

        /// The children Ready for `lesson`, in column order.
        func ready(_ lesson: CDLesson) throws -> [UUID] {
            viewModel.readyStudentIDs(for: try #require(lesson.id), studentOrder: studentOrder)
        }

        func ids(_ students: CDStudent...) throws -> [UUID] {
            try students.map { try #require($0.id) }
        }

        /// A presented record of `lesson` for `students`.
        @discardableResult
        func present(_ lesson: CDLesson, to students: [CDStudent]) throws -> CDLessonAssignment {
            let assignment = CDLessonAssignment(context: context)
            assignment.lessonID = try #require(lesson.id).uuidString
            assignment.studentIDs = students.map(\.cloudKitKey)
            assignment.markPresented(at: Date(timeIntervalSince1970: 1_780_000_000))
            try context.save()
            return assignment
        }

        /// Practice work on `lesson` for `student`, open or closed.
        @discardableResult
        func work(_ lesson: CDLesson, for student: CDStudent, status: WorkStatus) throws -> CDWorkModel {
            let work = CDWorkModel(context: context)
            work.lessonID = try #require(lesson.id).uuidString
            work.status = status
            work.createdAt = Date()
            let participant = CDWorkParticipantEntity(context: context)
            participant.studentID = student.cloudKitKey
            participant.work = work
            try context.save()
            return work
        }

        /// The grid catches up with records written behind its back.
        func rebuild() {
            viewModel.recomputeMatrix(context: context)
        }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let bruno = CoreDataTestHelpers.seedStudent(in: context, firstName: "Bruno", lastName: "Test")
        let chava = CoreDataTestHelpers.seedStudent(in: context, firstName: "Chava", lastName: "Test")

        func seed(_ sequence: String, orders: [Int]) -> [CDLesson] {
            orders.map { order in
                let lesson = CoreDataTestHelpers.seedLesson(
                    in: context, name: "\(sequence) \(order)", area: "Math", sequence: sequence
                )
                lesson.orderInSequence = Int64(order)
                return lesson
            }
        }
        let decimal = seed("Decimal", orders: [0, 1, 2, 7])
        let geometry = seed("Geometry", orders: [0, 1])

        let settings = CDLessonSequenceSettings(context: context)
        settings.id = UUID()
        settings.area = "Math"
        settings.sequence = "Geometry"
        settings.requiresPractice = false
        settings.requiresTeacherConfirmation = true
        try context.save()

        let suite = "ChecklistReadyLensTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.collapsedSequencesDefaults = defaults
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return Fixture(
            viewModel: viewModel, context: context, ada: ada, bruno: bruno, chava: chava,
            decimal: decimal, geometry: geometry
        )
    }

    // MARK: - The Ready Set

    @Test("The first lesson of a sequence is ready for every child with nothing on it")
    func firstLessonOfSequence() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let first = fixture.decimal[0]

        #expect(try fixture.ready(first) == fixture.ids(fixture.ada, fixture.bruno, fixture.chava))
        // Nothing has been given, so the lesson after it isn't ready for anyone.
        #expect(try fixture.ready(fixture.decimal[1]).isEmpty)

        // A plan or a presentation takes a child out of the set.
        viewModel.toggleScheduled(student: fixture.bruno, lesson: first, context: fixture.context)
        viewModel.togglePresented(student: fixture.chava, lesson: first, context: fixture.context)

        #expect(try fixture.ready(first) == fixture.ids(fixture.ada))
        #expect(viewModel.readyCount(for: first.id) == 1)
        #expect(viewModel.readyCount(for: fixture.decimal[1].id) == 0)
    }

    @Test("Practice and confirmation both hold the next lesson back until both are done")
    func practiceAndConfirmationGates() throws {
        let fixture = try makeFixture()
        let assignment = try fixture.present(fixture.decimal[0], to: [fixture.ada])
        fixture.rebuild()
        let next = fixture.decimal[1]
        // Presented, nothing practiced or confirmed.
        #expect(try fixture.ready(next).isEmpty)

        let work = try fixture.work(fixture.decimal[0], for: fixture.ada, status: .active)
        fixture.rebuild()
        #expect(try fixture.ready(next).isEmpty)

        // Practice closed; the guide still has to confirm her.
        work.status = .keepPracticing
        try fixture.context.save()
        fixture.rebuild()
        #expect(try fixture.ready(next).isEmpty)

        assignment.confirmStudent(try #require(fixture.ada.id))
        try fixture.context.save()
        fixture.rebuild()
        #expect(try fixture.ready(next) == fixture.ids(fixture.ada))
        // Only the child who met the gates.
        #expect(fixture.viewModel.readyCount(for: next.id) == 1)
    }

    @Test("A confirmation-only sequence needs no practice, but does need the confirmation")
    func confirmationOnlyGate() throws {
        let fixture = try makeFixture()
        let assignment = try fixture.present(fixture.geometry[0], to: [fixture.ada, fixture.bruno])
        assignment.confirmStudent(try #require(fixture.ada.id))
        try fixture.context.save()
        fixture.rebuild()

        // Ada: presented and confirmed, no work at all. Bruno: presented, not confirmed.
        #expect(try fixture.ready(fixture.geometry[1]) == fixture.ids(fixture.ada))
    }

    @Test("After a gap: the lesson past a skipped one or a gap in the numbering reads its own predecessor")
    func afterAGap() throws {
        let fixture = try makeFixture()
        // Ada was given Decimal 2 without Decimal 0 or 1, practiced and confirmed.
        let skippedTo = try fixture.present(fixture.decimal[2], to: [fixture.ada])
        try fixture.work(fixture.decimal[2], for: fixture.ada, status: .mastered)
        skippedTo.confirmStudent(try #require(fixture.ada.id))
        try fixture.context.save()
        fixture.rebuild()

        // Decimal 7 follows Decimal 2 though the numbers jump: ready for Ada.
        #expect(try fixture.ready(fixture.decimal[3]) == fixture.ids(fixture.ada))
        // The lesson she skipped still waits on Decimal 0, which she hasn't had.
        #expect(try fixture.ready(fixture.decimal[1]).isEmpty)
        // And the first lesson is still ready for her, with everyone else.
        #expect(try fixture.ready(fixture.decimal[0]) == fixture.ids(fixture.ada, fixture.bruno, fixture.chava))
    }

    // MARK: - Counts and Plan

    @Test("The toolbar's count is the Ready cells on screen, and follows the student filter")
    func readyTotal() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        // Decimal 0 and Geometry 0 are ready for all three; nothing else is.
        #expect(viewModel.readyTotal == 6)
        #expect(viewModel.readyTotal == viewModel.statusCounts[.ready])

        viewModel.studentFilterIDs = [try #require(fixture.ada.id)]
        viewModel.applyFilters()
        #expect(viewModel.readyTotal == 2)
        #expect(viewModel.readyCount(for: fixture.decimal[0].id) == 1)
    }

    @Test("A row's Plan drafts the lesson for exactly its ready children, and nothing when no one is")
    func planDraftsTheReadyChildren() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let first = fixture.decimal[0]
        let lessonID = try #require(first.id)
        viewModel.toggleScheduled(student: fixture.bruno, lesson: first, context: fixture.context)

        let draft = try #require(viewModel.makeReadyDraft(
            lessonID: lessonID, studentOrder: fixture.studentOrder, context: fixture.context
        ))
        let asMade = ChecklistDraftSnapshot(draft)
        #expect(Set(draft.studentIDs) == Set(try fixture.ids(fixture.ada, fixture.chava).map(\.uuidString)))
        #expect(draft.lessonID == lessonID.uuidString)
        #expect(!draft.isPresented)

        viewModel.discardUnusedDraft(draft, asMade: asMade, context: fixture.context)
        #expect(draft.isDeleted || draft.managedObjectContext == nil)

        let blocked = try #require(fixture.decimal[1].id)
        #expect(viewModel.makeReadyDraft(
            lessonID: blocked, studentOrder: fixture.studentOrder, context: fixture.context
        ) == nil)
    }

    @Test("The lens is display only: switching it changes no state the grid reads")
    func lensIsDisplayOnly() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let before = viewModel.matrixStates
        let counts = viewModel.statusCounts

        viewModel.lens = .ready
        #expect(viewModel.isReadyLens)
        #expect(viewModel.matrixStates == before)
        #expect(viewModel.statusCounts == counts)
        #expect(ChecklistLens.ready.title(readyCount: viewModel.readyTotal) == "Ready to Present (6)")
        #expect(ChecklistLens.allMarks.title(readyCount: 6) == "All Marks")
    }
}
