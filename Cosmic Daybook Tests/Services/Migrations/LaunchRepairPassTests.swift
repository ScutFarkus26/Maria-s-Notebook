import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Efficiency pass 2026-09-26 (Energy Fifty #12). Three launch repairs ran on
// the main-actor view context 3 s after launch: orphaned students on work rows
// (every launch, firing one `participants` fault, so one SELECT, per work row)
// and, on one launch in ten, the scheduled-day mirror and orphaned students on
// assignments. They now run inside MigrationRunner's background pass. These
// pin that the same rows change the same way as under the old code (kept in
// LaunchRepairOldCode), on the in-memory store and on SQLite, and that the
// work happens off the main thread and outside the view context.
//
// Two differences from the old code are on purpose (data model hunt
// 2026-10-05): the pass no longer rewrites the scheduled-day mirror (#49),
// and ids compare trimmed and upper-cased, so a lower-cased copy of a real
// student's id is kept (#23). `expectedFromOldCode` applies both.

@Suite("Launch repair pass")
@MainActor
struct LaunchRepairPassTests {
    private typealias Fixture = LaunchRepairFixture
    typealias Store = LaunchRepairFixture.Store

    /// What the old code left, with the two intended differences: the
    /// assignments keep the scheduled days they were seeded with, and Cy,
    /// named in lower case on work 5 and assignment 3, stays.
    private static func expectedFromOldCode(
        _ old: Fixture.Snapshot, seeded: Fixture.Snapshot
    ) -> Fixture.Snapshot {
        var expected = old
        expected.assignmentDays = seeded.assignmentDays
        let cy = Fixture.cy.uuidString.lowercased()
        expected.workStudents[Fixture.workID(5)] = cy
        expected.assignmentStudents[Fixture.assignmentID(3)] = [cy]
        return expected
    }

    /// The launch sweep without its disk and defaults side effects (note
    /// images, the check-in repair's first-run flag): dedup, then a save.
    nonisolated private static func dedupSweep(_ context: NSManagedObjectContext) -> [String: Int] {
        let results = DataCleanupService.deduplicateAllModels(using: context)
        if context.hasChanges {
            context.safeSave()
        }
        return results
    }

    @Test("The background pass changes the same rows the same way as the view-context code",
          arguments: [Store.inMemory, .sqlite])
    func sameRowsRepairedTheSameWay(store: Store) async throws {
        let (old, oldOwner) = try store.make()
        let (new, newOwner) = try store.make()
        defer { withExtendedLifetime((oldOwner, newOwner)) {} }
        try Fixture.seed(old)
        try Fixture.seed(new)
        let seeded = Fixture.snapshot(of: new)
        #expect(Fixture.snapshot(of: old) == seeded)

        // Old: awaited on the main actor with the view context, in launch order
        // (less the scheduled-day mirror, which the pass no longer rewrites).
        await LaunchRepairOldCode.cleanOrphanedStudentIDs(using: old)
        await LaunchRepairOldCode.cleanOrphanedWorkStudentIDs(using: old)

        // New: one pass on a background context.
        let outcome = await MigrationRunner.runPass(
            on: Fixture.backgroundContext(beside: new), includeIntegrityRepairs: true, firstDownloadPending: false
        ) { _ in [:] }

        let oldResult = Fixture.snapshot(of: old)
        let newResult = Fixture.snapshot(of: new)
        #expect(newResult == Self.expectedFromOldCode(oldResult, seeded: seeded))

        // And the fixture really exercised every repair.
        let (ada, ben, cy) = (Fixture.ada.uuidString, Fixture.ben.uuidString, Fixture.cy.uuidString)
        let clearedWork: [UUID: String] = [
            Fixture.workID(1): ada, Fixture.workID(2): "", Fixture.workID(3): "", Fixture.workID(4): "",
            Fixture.workID(5): cy.lowercased(), Fixture.workID(6): ben, Fixture.workID(7): cy
        ]
        let keptParticipants: Set<UUID> = Set([1, 3, 5, 6, 8, 9].map(Fixture.participantID))
        #expect(newResult.workStudents == clearedWork)
        #expect(Set(newResult.participantStudents.keys) == keptParticipants)
        #expect(newResult.participantWorks[Fixture.participantID(9)] == nil)
        #expect(newResult.assignmentStudents[Fixture.assignmentID(1)] == [ada])
        #expect(newResult.assignmentStudents[Fixture.assignmentID(3)] == [cy.lowercased()])
        #expect(newResult.assignmentStudents[Fixture.assignmentID(5)] == [cy, ben])
        // The scheduled-day mirror is left as it was, drift and all (#49).
        #expect(newResult.assignmentDays == seeded.assignmentDays)
        #expect(newResult.assignmentDays[Fixture.assignmentID(1)] == .distantPast)
        #expect(newResult != seeded)
        #expect(outcome.workRowsCleaned == 4)
        #expect(outcome.integrityRepairSeconds != nil)
    }

    @Test("With the launch dedup between them, the repairs see what it left, as before",
          arguments: [Store.inMemory, .sqlite])
    func sameRowsRepairedAroundTheDedup(store: Store) async throws {
        let (old, oldOwner) = try store.make()
        let (new, newOwner) = try store.make()
        defer { withExtendedLifetime((oldOwner, newOwner)) {} }
        for context in [old, new] {
            try Fixture.seed(context)
            try Fixture.seedDuplicates(context)
            // Nothing registered, as for rows the launch UI hasn't shown.
            context.reset()
        }
        let seeded = Fixture.snapshot(of: new)

        // Old: the assignment repair on the view context, the dedup on a
        // background context, then the work repair on the view context.
        await LaunchRepairOldCode.cleanOrphanedStudentIDs(using: old)
        let oldSweep = Fixture.backgroundContext(beside: old)
        let oldDuplicates = await oldSweep.perform { Self.dedupSweep(oldSweep) }
        await LaunchRepairOldCode.cleanOrphanedWorkStudentIDs(using: old)

        // New: all three inside the pass, the dedup in between.
        let outcome = await MigrationRunner.runPass(
            on: Fixture.backgroundContext(beside: new), includeIntegrityRepairs: true, firstDownloadPending: false
        ) { Self.dedupSweep($0) }

        let folded: [String: Int] = ["Student": 1, "WorkModel": 1]
        #expect(outcome.duplicatesRemoved == oldDuplicates)
        #expect(outcome.duplicatesRemoved == folded)
        let newResult = Fixture.snapshot(of: new)
        #expect(newResult == Self.expectedFromOldCode(Fixture.snapshot(of: old), seeded: seeded))
        // The copy's participants moved onto work 2; the one naming a departed student then went.
        #expect(newResult.participantWorks[Fixture.participantID(11)] == Fixture.workID(2))
        #expect(newResult.participantStudents[Fixture.participantID(10)] == nil)
        #expect(newResult.participantStudents[Fixture.participantID(2)] == nil)
        #expect(newResult.rowCounts["WorkModel"] == 7)
    }

    @Test("The repairs run and save on the background context's queue, not on the main thread")
    func repairsRunOffTheMainThread() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let view = stack.viewContext
        try Fixture.seed(view)
        view.reset()
        let recorder = ContextSaveRecorder(coordinator: view.persistentStoreCoordinator)

        let background = stack.newBackgroundContext()
        let outcome = await MigrationRunner.runPass(
            on: background, includeIntegrityRepairs: true, firstDownloadPending: false
        ) { _ in [:] }
        let saves = recorder.finish()

        #expect(outcome.workRowsCleaned == 4)
        // One save per repair that changed rows: assignment students, work students.
        let savedEntities: [Set<String>] = [["LessonAssignment"], ["WorkModel", "WorkParticipantEntity"]]
        #expect(saves.map(\.entityNames) == savedEntities)
        #expect(saves.allSatisfy { !$0.onMainThread })
        #expect(saves.allSatisfy { $0.context == ObjectIdentifier(background) })
        // The old code fetched every student, work, participant and assignment
        // into the view context; the pass registers none of them there.
        let registered = Set(view.registeredObjects.compactMap { $0.entity.name })
        let repairedEntities: Set<String> = ["Student", "WorkModel", "WorkParticipantEntity", "LessonAssignment"]
        #expect(registered.isDisjoint(with: repairedEntities))
    }

    @Test("Without the integrity flag the assignment rows are left alone")
    func assignmentsUntouchedWithoutTheFlag() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        try Fixture.seed(stack.viewContext)
        let seeded = Fixture.snapshot(of: stack.viewContext)

        let outcome = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: false, firstDownloadPending: false
        ) { _ in [:] }

        let result = Fixture.snapshot(of: stack.viewContext)
        #expect(outcome.integrityRepairSeconds == nil)
        #expect(result.assignmentStudents == seeded.assignmentStudents)
        #expect(result.assignmentDays == seeded.assignmentDays)
        #expect(outcome.workRowsCleaned == 4)
    }

    @Test("A step that leaves changes unsaved doesn't carry them into the next step's save")
    func unsavedChangesAreDroppedBetweenSteps() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        try Fixture.seed(stack.viewContext)

        // A sweep whose save "failed": it changed a row and left it unsaved.
        let firstWork = Fixture.workID(1)
        let outcome = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: false, firstDownloadPending: false
        ) { context in
            let request = CDFetchRequest(CDWorkModel.self)
            request.predicate = NSPredicate(format: "id == %@", firstWork as CVarArg)
            context.safeFetchFirst(request)?.title = "Never saved"
            return [:]
        }

        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = stack.container.persistentStoreCoordinator
        #expect(reader.object(CDWorkModel.self, id: Fixture.workID(1))?.title == "Work 1")
        // The work repair after it still saved its own changes.
        #expect(outcome.workRowsCleaned == 4)
        #expect(reader.object(CDWorkModel.self, id: Fixture.workID(2))?.studentID == "")
    }

    @Test("The work read loads every participant up front instead of one fault per row")
    func participantsArePrefetched() throws {
        // SQLite: relationship faults are real there (the in-memory store has none to fire).
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        for number in 1...200 {
            Fixture.work(number, studentID: "", participants: [(2 * number, "a"), (2 * number + 1, "b")], in: context)
        }
        try context.save()

        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator
        let plain = reader.safeFetch(CDFetchRequest(CDWorkModel.self))
        let unloadedBefore = plain.filter { $0.hasFault(forRelationshipNamed: "participants") }.count
        reader.reset()
        let prefetched = reader.safeFetch(DataCleanupService.orphanCleanupWorkFetch())
        let unloadedAfter = prefetched.filter { $0.hasFault(forRelationshipNamed: "participants") }.count

        // Each unloaded relationship costs a SELECT when the cleanup reads it.
        #expect(plain.count == 200)
        #expect(unloadedBefore == 200)
        #expect(prefetched.count == 200)
        #expect(unloadedAfter == 0)
        #expect(prefetched.allSatisfy { ($0.participants?.count ?? 0) == 2 })
    }

    @Test("Student ids read as one column give the set the object read gave", arguments: [Store.inMemory, .sqlite])
    func studentIDsMatchTheObjectRead(store: Store) throws {
        let (context, owner) = try store.make()
        defer { withExtendedLifetime(owner) {} }
        // No students: nil, so neither cleanup touches a row.
        #expect(DataCleanupService.studentIDStrings(using: context) == nil)

        // Only a student with no id: the old read went ahead with nothing
        // valid (a random UUID matches nothing), and so does this one.
        CoreDataTestHelpers.seedStudent(in: context, firstName: "No", lastName: "Id").id = nil
        try context.save()
        #expect(DataCleanupService.studentIDStrings(using: context) == [])

        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        ada.id = Fixture.ada
        try context.save()
        #expect(DataCleanupService.studentIDStrings(using: context) == [Fixture.ada.uuidString])

        // Unsaved changes: a column read can't see them, so the object read answers.
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben").id = Fixture.ben
        context.delete(ada)
        #expect(DataCleanupService.studentIDStrings(using: context) == [Fixture.ben.uuidString])
    }
}
