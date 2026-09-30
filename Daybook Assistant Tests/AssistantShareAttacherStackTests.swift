import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The attach queue across a stack's life: the iCloud account arriving after
// launch rebuilds the stack under a running pass (`AssistantStack.rebuild`),
// and a closed stack can't read the marks it was asked about. Uses
// `FakeShare` from AssistantShareAttacherTests.
@Suite("Assistant share attacher across stacks")
@MainActor
struct AssistantShareAttacherStackTests {

    private let stack: CoreDataStack
    private let defaults: UserDefaults
    private let share = FakeShare()

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        defaults = AssistantTestSupport.makeDefaults()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    private func launch() -> AssistantShareAttacher {
        AssistantShareAttacher(defaults: defaults, sleep: share.sleep, attempt: share.attempt)
    }

    private func marks(_ count: Int) -> [NSManagedObjectID] {
        let records = (0..<count).map { _ in
            let record = CDAttendanceRecord(context: context)
            record.id = UUID()
            return record
        }
        #expect(context.safeSave())
        return records.map(\.objectID)
    }

    private func attach(_ ids: [NSManagedObjectID], with attacher: AssistantShareAttacher) async {
        attacher.attach(ids, container: stack.container, context: context)
        await attacher.waitUntilIdle()
    }

    // Logic-break sweep 2026-09-29, F1. A pass kept the stack it started
    // with. When the iCloud account arrived mid-pass and the stack was
    // rebuilt, the new stack's flush only asked the pass to go round again,
    // on the old stack: nothing resolved there, and the marks were forgotten.
    @Test("A pass that outlives its stack hands its marks to the rebuilt one")
    func rebuiltStackTakesOver() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttacherRebuild-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("private.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = try CoreDataStack(enableCloudKit: false, localStoreURL: url)
        let ids = (0..<2).map { _ in
            let record = CDAttendanceRecord(context: old.viewContext)
            record.id = UUID()
            return record
        }
        #expect(old.viewContext.safeSave())
        let oldIDs = ids.map(\.objectID)

        let attacher = launch()
        share.holdsNextAttempt = true
        share.refusesNextAttempt = true
        attacher.attach(oldIDs, container: old.container, context: old.viewContext)
        #expect(await waitUntil { share.isHolding })

        // What AssistantStack.rebuild does: the old stores come off, and a
        // new stack opens the same files.
        let coordinator = old.container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try coordinator.remove(store) }
        let rebuilt = try CoreDataStack(enableCloudKit: false, localStoreURL: url)
        attacher.flush(container: rebuilt.container, context: rebuilt.viewContext)
        share.release()
        await attacher.waitUntilIdle()

        #expect(share.attempts.count == 2)
        #expect(share.attempts.last?.map { $0.uriRepresentation() } == oldIDs.map { $0.uriRepresentation() })
        #expect(share.contexts.last === rebuilt.viewContext)
        #expect(attacher.pending.isEmpty)
    }

    @Test("Marks a closed stack can't read stay waiting; marks deleted from a live store are dropped")
    func unresolvableMarksAreKeptUnlessGone() async throws {
        let attacher = launch()
        let ids = marks(2)
        share.refusesEverything = true
        await attach(ids, with: attacher)
        #expect(attacher.pending.count == 2)

        // A live store: the deleted mark goes, the other is tried.
        share.refusesEverything = false
        context.delete(try context.existingObject(with: ids[0]))
        #expect(context.safeSave())
        attacher.retryWaiting()
        await attacher.waitUntilIdle()
        #expect(share.attempts.last == [ids[1]])
        #expect(attacher.pending.isEmpty)

        // A closed stack reads nothing, and forgets nothing.
        let more = marks(1)
        share.refusesEverything = true
        await attach(more, with: attacher)
        let coordinator = stack.container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try coordinator.remove(store) }
        attacher.retryWaiting()
        await attacher.waitUntilIdle()
        #expect(attacher.pending == more.map { $0.uriRepresentation() })
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
