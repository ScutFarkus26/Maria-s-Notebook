import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Sync and sharing bug hunt 2026-10-05 (#6, #8 and the Daybook Assistant
// list): what Leave and a stack rebuild do with the attach queue, marks that
// land in another share zone, the waiting count the sync line reads, and
// records another screen left in the context. Uses `FakeShare` from
// AssistantShareAttacherTests.
@Suite("Assistant share attacher: Leave, rebuilds and zones")
@MainActor
struct AssistantShareAttacherLeaveTests {

    private let stack: CoreDataStack
    private let defaults: UserDefaults
    private let share = FakeShare()

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        defaults = AssistantTestSupport.makeDefaults()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    private func launch(strays: Strays? = nil) -> AssistantShareAttacher {
        AssistantShareAttacher(
            defaults: defaults,
            sleep: share.sleep,
            attempt: share.attempt,
            zoneCheck: { ids, _, _ in strays.map { ids.filter($0.ids.contains) } ?? [] }
        )
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

    // MARK: - Leave

    @Test("Leave's forget empties the list, and a pass running then doesn't put its marks back")
    func forgetDuringPass() async {
        let attacher = launch()
        let ids = marks(2)
        share.refusesEverything = true
        share.holdsNextAttempt = true
        attacher.attach(ids, container: stack.container, context: context)
        #expect(await waitUntil { share.isHolding })
        #expect(attacher.pendingCount == 2)

        attacher.forgetWaiting()
        share.release()
        await attacher.waitUntilIdle()
        #expect(attacher.pending.isEmpty)
        #expect(attacher.pendingCount == 0)
        #expect(share.rests.isEmpty)
    }

    @Test("Forgetting the class's state on this iPhone forgets its waiting marks too")
    func localStateForgetsTheList() async {
        let attacher = launch()
        share.refusesEverything = true
        attacher.attach(marks(1), container: stack.container, context: context)
        await attacher.waitUntilIdle()
        #expect(defaults.stringArray(forKey: AssistantShareAttacher.listKey)?.count == 1)

        AssistantClassroomLocalState.forget(defaults: defaults)
        #expect(defaults.object(forKey: AssistantShareAttacher.listKey) == nil)
        #expect(launch().pending.isEmpty)
    }

    @Test("While held no pass starts and new marks wait; release tries them")
    func heldThenReleased() async {
        let attacher = launch()
        let ids = marks(2)
        attacher.hold()
        attacher.attach(ids, container: stack.container, context: context)
        await attacher.waitUntilIdle()
        #expect(share.attempts.isEmpty)
        #expect(attacher.pending == ids.map { $0.uriRepresentation() })

        attacher.release()
        await attacher.waitUntilIdle()
        #expect(share.attempts == [ids])
        #expect(attacher.pending.isEmpty)
    }

    @Test("Waiting for a pass gives up at its limit, and returns once the pass ends")
    func boundedWait() async {
        let attacher = launch()
        share.holdsNextAttempt = true
        attacher.attach(marks(1), container: stack.container, context: context)
        #expect(await waitUntil { share.isHolding })
        #expect(await !attacher.waitUntilIdle(upTo: .milliseconds(100)))

        share.release()
        #expect(await attacher.waitUntilIdle(upTo: .seconds(30)))
    }

    // MARK: - The class's own zone

    @Test("A mark that lands in another share zone stays waiting and isn't tried again at once")
    func wrongZoneStaysUnsent() async {
        let ids = marks(2)
        let strays = Strays(ids: [ids[1]])
        let attacher = launch(strays: strays)
        attacher.attach(ids, container: stack.container, context: context)
        await attacher.waitUntilIdle()
        #expect(share.attempts == [ids])
        #expect(attacher.pending == [ids[1].uriRepresentation()])
        #expect(attacher.pendingCount == 1)
        // Counted as a refusal: the backlog rests rather than going round.
        #expect(share.rests == [AssistantShareAttacher.rest(afterFailures: 1)])

        // In the class's zone after all (the store caught up): it goes.
        strays.ids = []
        attacher.retryWaiting()
        await attacher.waitUntilIdle()
        #expect(attacher.pending.isEmpty)
    }

    @Test("Strays are the records in another zone or in no share")
    func straysAmongZones() {
        let ids = marks(3)
        let pinned = "com.apple.coredata.cloudkit.share.DB5879EF"
        let zones = [ids[0]: pinned, ids[1]: "com.apple.coredata.cloudkit.share.OTHER"]
        #expect(AssistantShareAttacher.strays(among: ids, zones: zones, pinned: pinned) == [ids[1], ids[2]])
    }

    @Test("Without a pin to compare with, nothing counts as a stray")
    func noPinNoStrays() async {
        let ids = marks(1)
        let strays = await AssistantShareAttacher.outsidePinnedZone(ids, container: stack.container, context: context)
        #expect(strays.isEmpty)
    }

    // MARK: - A stack closing

    @Test("A container with no stores open keeps its marks; one store with no shared store has nothing to file")
    func closedStackKeepsMarks() async throws {
        let ids = marks(2)
        let open = await CDAttendanceStore.attachNewRecordsToClassroomShare(
            ids, container: stack.container, pinContext: context
        )
        #expect(open.left.isEmpty)

        let coordinator = stack.container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try coordinator.remove(store) }
        let closed = await CDAttendanceStore.attachNewRecordsToClassroomShare(
            ids, container: stack.container, pinContext: context
        )
        #expect(closed.left == ids)
        #expect(!closed.mirroringStopped)
    }

    // MARK: - Saves

    @Test("A save files every classroom record it inserts, not only the caller's")
    func saveFilesOtherInserts() {
        let mine = CDAttendanceRecord(context: context)
        mine.id = UUID()
        // Left in the context by a screen whose own save failed.
        let leftOver = CDAttendanceRecord(context: context)
        leftOver.id = UUID()
        let notShared = CDClassroomMembership(context: context)
        notShared.id = UUID()

        let filed = AssistantSave.recordsToFile(created: [mine], in: context)
        #expect(filed.first === mine)
        #expect(filed.count == 2)
        #expect(filed.contains { $0 === leftOver })
        #expect(!filed.contains { $0 === notShared })
        context.rollback()
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

/// The records a test's zone check says went into another share.
@MainActor
final class Strays {
    var ids: Set<NSManagedObjectID>
    init(ids: Set<NSManagedObjectID>) { self.ids = ids }
}
