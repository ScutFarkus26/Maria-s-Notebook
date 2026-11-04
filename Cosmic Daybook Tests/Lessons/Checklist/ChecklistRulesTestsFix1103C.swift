import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-11-03, the Checklist's rules and refreshes (#5's ready-engine
/// side, #13, #14, #15): the ready rule honors a lesson's own progression
/// settings, a failed save is taken back, the columns follow the roster, and
/// Mastered marks the latest history row.
@Suite("Checklist rules and refreshes (11-03 C)")
@MainActor
struct ChecklistRulesFix1103CTests {

    typealias Fixture = ChecklistFix1103CFixture

    // MARK: - #5 The ready rule honors the lesson's own settings

    /// The cell's level for the second lesson, and the queue's.
    private func tiers(_ fixture: Fixture, _ student: CDStudent) throws -> (cell: ReadinessTier, queue: ReadinessTier) {
        let matrix = ClassGridEngine.buildMatrix(
            students: [fixture.maya, fixture.eli], lessons: [fixture.first, fixture.second], context: fixture.context
        )
        let studentUUID = try #require(student.id)
        let secondUUID = try #require(fixture.second.id)
        let state = try #require(matrix[studentUUID]?[secondUUID])
        let cell: ReadinessTier = state.blockingReason != .none
            ? .notReady : (state.checkFirstReasons.isEmpty ? .ready : .almostReady)
        let studentID = studentUUID.uuidString
        let index = PresentationRecordIndex(students: [studentID], in: fixture.context)
        let items = ReadyForNextEngine.items(
            studentIDs: [studentID], lessons: [fixture.first, fixture.second], index: index, in: fixture.context
        )
        let secondID = try #require(fixture.second.id).uuidString
        let queue = items.first { $0.nextLessonID == secondID }?.tier ?? .notReady
        return (cell, queue)
    }

    @Test("#5: a lesson set to Requires Confirmation: No doesn't hold an unconfirmed child back")
    func confirmationOverrideHonored() throws {
        let fixture = try Fixture.make()
        fixture.first.confirmationOverride = .no
        try fixture.give([fixture.maya], on: "2026-10-20")
        try fixture.context.save()

        let maya = try tiers(fixture, fixture.maya)
        #expect(maya.cell == .ready)
        #expect(maya.queue == .ready)
        // Eli wasn't given it: still not ready.
        #expect(try tiers(fixture, fixture.eli).cell == .notReady)
    }

    @Test("#5: with no override, an unconfirmed child is still not ready")
    func confirmationStillRequiredByDefault() throws {
        let fixture = try Fixture.make()
        try fixture.give([fixture.maya], on: "2026-10-20")
        try fixture.context.save()

        let maya = try tiers(fixture, fixture.maya)
        #expect(maya.cell == .notReady)
        #expect(maya.queue == .notReady)
    }

    @Test("#5: a sequence set not to require confirmation is read the way Presentations reads it")
    func sequenceSettingHonored() throws {
        let fixture = try Fixture.make()
        let settings = CDLessonSequenceSettings(context: fixture.context)
        settings.area = "Math"
        settings.sequence = "Decimal"
        settings.requiresPractice = true
        settings.requiresTeacherConfirmation = false
        try fixture.give([fixture.maya], on: "2026-10-20")
        try fixture.context.save()

        let maya = try tiers(fixture, fixture.maya)
        #expect(maya.cell == .ready)
        #expect(maya.queue == .ready)
    }

    /// Open work never holds a child back in this rule, so the practice setting
    /// changes nothing: both views still ask for a look first (Simplify the app,
    /// Phase 3; `ReadyForNextEngineTests.openWorkCountsWithoutThePracticeSetting`).
    @Test("#5: with Requires Practice: No, open work is still worth a look in the cell and the queue")
    func practiceOverrideKeepsCheckFirst() throws {
        let fixture = try Fixture.make()
        fixture.first.practiceOverride = .no
        let given = try fixture.give([fixture.maya], on: "2026-10-20", confirming: [fixture.maya])
        try fixture.context.save()
        _ = try WorkRepository(context: fixture.context).createWork(
            studentID: try #require(fixture.maya.id), lessonID: try #require(fixture.first.id),
            kind: .practiceLesson, presentationID: given.id, saveImmediately: false
        )
        try fixture.context.save()

        let maya = try tiers(fixture, fixture.maya)
        #expect(maya.cell == .almostReady)
        #expect(maya.queue == .almostReady)
    }

    // MARK: - #13 A failed save is taken back

    /// A view context whose saves fail while `failsSaves` is on.
    final class SaveFailingContext: NSManagedObjectContext, @unchecked Sendable {
        var failsSaves = false

        override func save() throws {
            if failsSaves {
                throw NSError(domain: "ChecklistRulesFix1103CTests", code: 1)
            }
            try super.save()
        }
    }

    /// A fixture over a context whose saves can be made to fail, and the stack it lives on.
    struct FailingFixture {
        let fixture: Fixture
        let context: SaveFailingContext
        let stack: CoreDataStack
    }

    private func makeFailingFixture() throws -> FailingFixture {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = SaveFailingContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = stack.viewContext.persistentStoreCoordinator
        return FailingFixture(fixture: try Fixture.make(context: context), context: context, stack: stack)
    }

    @Test("#13: a cell mark whose save fails is taken back, and the cell reads what is stored")
    func failedCellSaveIsTakenBack() throws {
        let failing = try makeFailingFixture()
        let fixture = failing.fixture
        failing.context.failsSaves = true

        fixture.viewModel.perform(
            .markPresented, on: try fixture.cell(fixture.maya, fixture.first), context: fixture.context
        )

        #expect(fixture.assignments(fixture.maya, fixture.first).isEmpty)
        #expect(fixture.status(fixture.maya, fixture.first) == .ready)
        #expect(!failing.context.hasChanges)
    }

    @Test("#13: a selection mark whose save fails is taken back")
    func failedBatchSaveIsTakenBack() throws {
        let failing = try makeFailingFixture()
        let fixture = failing.fixture
        failing.context.failsSaves = true

        fixture.viewModel.selectedCells = [
            try fixture.cell(fixture.maya, fixture.first), try fixture.cell(fixture.eli, fixture.first)
        ]
        fixture.viewModel.batchMarkPresented(context: fixture.context)

        #expect(fixture.assignments(fixture.maya, fixture.first).isEmpty)
        #expect(fixture.assignments(fixture.eli, fixture.first).isEmpty)
        #expect(fixture.status(fixture.maya, fixture.first) == .ready)
        #expect(!failing.context.hasChanges)
    }

    // MARK: - #14 The columns follow the roster

    @Test("#14: a refresh brings in a new child and drops one who left")
    func refreshFollowsRoster() throws {
        let fixture = try Fixture.make()
        let noa = CoreDataTestHelpers.seedStudent(in: fixture.context, firstName: "Noa", lastName: "Levi")
        fixture.eli.enrollmentStatus = .withdrawn
        fixture.eli.dateWithdrawn = Date()
        try fixture.context.save()

        fixture.viewModel.refreshMatrix(context: fixture.context)

        let columns = Set(fixture.viewModel.rosterStudents.compactMap(\.id))
        #expect(columns == Set([fixture.maya.id, noa.id].compactMap { $0 }))
        #expect(Set(fixture.viewModel.students.compactMap(\.id)) == columns)
        #expect(fixture.status(noa, fixture.first) == .ready)
    }

    @Test("#14: a refresh keeps hidden test students hidden")
    func refreshKeepsTestStudentsHidden() throws {
        let fixture = try Fixture.make()
        fixture.viewModel.applyVisibilityFilter(context: fixture.context, show: false, namesRaw: "Eli Park")
        #expect(!fixture.viewModel.rosterStudents.contains { $0.id == fixture.eli.id })

        fixture.viewModel.refreshMatrix(context: fixture.context)

        #expect(!fixture.viewModel.rosterStudents.contains { $0.id == fixture.eli.id })
        #expect(fixture.viewModel.rosterStudents.contains { $0.id == fixture.maya.id })
    }

    // MARK: - #15 Mastered marks the latest row

    @Test("#15: the cell's Mastered marks her latest history row")
    func cellMasteredMarksLatestRow() throws {
        // On disk, so an unsorted fetch returns rows in the order they were made.
        let fixture = try Fixture.make(context: try CoreDataTestHelpers.makeSplitStoreContext())
        let rows = try givenTwice(fixture)
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.perform(
            .markComplete, on: try fixture.cell(fixture.maya, fixture.first), context: fixture.context
        )

        #expect(rows.newer.state == .proficient)
        #expect(rows.newer.masteredAt != nil)
        #expect(rows.older.state == .presented)
    }

    @Test("#15: the selection's Mastered marks her latest history row")
    func batchMasteredMarksLatestRow() throws {
        let fixture = try Fixture.make(context: try CoreDataTestHelpers.makeSplitStoreContext())
        let rows = try givenTwice(fixture)
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.selectedCells = [try fixture.cell(fixture.maya, fixture.first)]
        fixture.viewModel.batchMarkProficient(context: fixture.context)

        #expect(rows.newer.state == .proficient)
        #expect(rows.newer.masteredAt != nil)
        #expect(rows.older.state == .presented)
    }

    /// Maya given the first lesson in September and again in October, the older row made first.
    private func givenTwice(_ fixture: Fixture) throws -> (older: CDLessonPresentation, newer: CDLessonPresentation) {
        let september = try fixture.give([fixture.maya], on: "2026-09-08")
        let older = fixture.historyRow(fixture.maya, for: september)
        try fixture.context.save()
        let october = try fixture.give([fixture.maya], on: "2026-10-20")
        let newer = fixture.historyRow(fixture.maya, for: october)
        try fixture.context.save()
        return (older, newer)
    }
}
