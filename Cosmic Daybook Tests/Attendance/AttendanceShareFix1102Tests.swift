import Foundation
@preconcurrency import CoreData
import CloudKit
import Testing
@testable import CosmicDaybook

// The 2026-11-02 sync, sharing and backup hunt, the attendance store's part:
// an assistant added as "View only" could mark, and the marks never reached
// the guide (#29); a notebook joined as an assistant left which share zone its
// marks joined to Core Data (#33); and Leave's deletes saved with no author
// and the error merge policy (#53).
@Suite("Attendance share fixes 2026-11-02", .serialized)
@MainActor
struct AttendanceShareFix1102Tests {

    // MARK: - #29 View only

    // The store-wide `canModifyManagedObjects(in:)` used to count as View
    // only too, but a zone a stopped share release left behind flipped it
    // while the class zone was writable, and an assistant the share let make
    // changes was told her guide had set View only (2026-11-06). Only the
    // share's word counts now; no word leaves the last answer standing.
    @Test("View only is the share's word on this participant, never the store's or a failed save")
    func viewOnlyRule() {
        let answer = ClassroomSharingService.viewOnlyAnswer
        #expect(answer(.readOnly) == true, "the guide added her as View only")
        #expect(answer(.readWrite) == false, "even while the store-wide answer says no")
        #expect(answer(nil) == nil, "a share that doesn't say leaves the last answer")
        #expect(answer(.unknown) == nil)
        #expect(answer(CKShare.ParticipantPermission.none) == nil)
    }

    @Test("A View only assistant can't mark; the guide still can")
    func viewOnlyCantMark() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = CDStudent(context: context)
        student.id = UUID()
        let day = AppCalendar.startOfDay(Date())
        let wasViewOnly = ClassroomPermissions.shareIsViewOnly
        defer { ClassroomPermissions.shareIsViewOnly = wasViewOnly }

        ClassroomPermissions.shareIsViewOnly = false
        #expect(CDAttendanceStore(context: context, role: .assistant).canWrite(on: day))

        // Before: the grid let her mark, and the marks waited for the share for good.
        ClassroomPermissions.shareIsViewOnly = true
        let assistant = CDAttendanceStore(context: context, role: .assistant)
        #expect(!assistant.canWrite(on: day))
        #expect(try assistant.ensureRecord(for: student, on: day) == nil)
        #expect(!ClassroomPermissions.canWrite(entityName: "SupplyTransaction", role: .assistant))
        #expect(CDAttendanceStore(context: context, role: .leadGuide).canWrite(on: day))
    }

    // MARK: - #33 A notebook joined as an assistant

    @Test("A notebook joined as an assistant puts the marks it saves into the share; a guide's don't go")
    func notebookAssistantFilesItsMarks() async throws {
        let fixture = try TwoStoreHistoryFixture()
        defer { fixture.removeFiles() }
        let context = fixture.container.viewContext
        let tries = Tries()
        let role = Role()
        let filing = AssistantRoleShareFiling(
            attempt: tries.attempt, role: { _ in role.now }, sleep: { _ in throw CancellationError() }
        )
        filing.watch(context, container: fixture.container)

        // The guide's own notebook: nothing for this to do.
        role.now = .leadGuide
        _ = try Self.mark(in: context, store: fixture.sharedStore)
        try await Task.sleep(for: .milliseconds(100))
        await filing.waitUntilIdle()
        #expect(tries.attempts.isEmpty)

        // Joined as an assistant: before, the mark was left to Core Data.
        role.now = .assistant
        tries.refusesNext = true
        let first = try Self.mark(in: context, store: fixture.sharedStore)
        #expect(await Self.waitUntil { tries.attempts.count == 1 })
        await filing.waitUntilIdle()
        #expect(tries.attempts == [[first]])
        #expect(filing.waiting == [first], "refused: it waits")

        // A record in the private store isn't hers to file.
        let privateRecord = try Self.mark(in: context, store: fixture.privateStore)
        try await Task.sleep(for: .milliseconds(100))
        await filing.waitUntilIdle()
        #expect(tries.attempts.count == 1)
        #expect(!filing.waiting.contains(privateRecord))

        // The next mark takes the one that waited with it.
        let second = try Self.mark(in: context, store: fixture.sharedStore)
        #expect(await Self.waitUntil { tries.attempts.count == 2 })
        await filing.waitUntilIdle()
        #expect(Set(tries.attempts.last ?? []) == [first, second])
        #expect(filing.waiting.isEmpty)
    }

    // MARK: - #53 Leave's deletes

    @Test("Leave's delete of unshared marks saves with the app's author and merge policy")
    func leaveDeleteHasAnAuthor() async throws {
        // On disk: an in-memory store keeps no history.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leave-delete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stack = try CoreDataStack(
            enableCloudKit: false, localStoreURL: directory.appendingPathComponent("notebook.sqlite")
        )
        let record = CDAttendanceRecord(context: stack.viewContext)
        record.id = UUID()
        try stack.viewContext.save()
        let token = stack.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)

        let deleted = try await CDAttendanceStore.deleteUnsharedRecords([record.objectID], in: stack)
        #expect(deleted == 1)

        // Before: a context straight from the container, with no author.
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.resultType = .transactionsAndChanges
        let result = try stack.viewContext.execute(request) as? NSPersistentHistoryResult
        let transactions = try #require(result?.result as? [NSPersistentHistoryTransaction])
        let delete = try #require(transactions.last)
        #expect(delete.author == PersistentHistoryProcessor.transactionAuthor)
        #expect(delete.changes?.contains { $0.changeType == .delete } == true)
    }

    // MARK: - Helpers

    private static func waitUntil(
        upTo limit: Duration = .seconds(10), _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private static func mark(in context: NSManagedObjectContext, store: NSPersistentStore) throws -> NSManagedObjectID {
        let record = CDAttendanceRecord(context: context)
        record.id = UUID()
        context.assign(record, to: store)
        try context.save()
        return record.objectID
    }
}

@MainActor
private final class Tries {
    private(set) var attempts: [[NSManagedObjectID]] = []
    var refusesNext = false

    var attempt: AssistantRoleShareFiling.Attempt {
        { [self] ids, _, _ in
            attempts.append(ids)
            if refusesNext {
                refusesNext = false
                return .init(left: ids)
            }
            return .init(left: [])
        }
    }
}

@MainActor
private final class Role {
    var now: CDClassroomMembership.ClassroomRole = .leadGuide
}
