import Foundation
import CoreData
import CloudKit
import Testing
@testable import Daybook_Assistant

// The review of the 2026-10-20 sync and joining fixes (review b), sending:
// Leave and Wait gave the wrong advice while sending was stuck (item 3); a
// let-go call kept sending to the closed stack (4); CloudKit's wait was cut
// short and the backlog waited for a tap (6); Wait didn't wait for a save
// from before a relaunch (7); a second Download from iCloud again showed the
// join screen (9); and the wiring behind those rules (10).
@Suite("Assistant sending review fixes 2026-10-20", .serialized)
@MainActor
struct AssistantSendingFix1020RoundB {

    // MARK: - 3. Advice while sending is stuck

    @Test("Leave and Wait say to quit and reopen while sending is stuck")
    func stuckAdvice() {
        let stuck = AssistantLeaveError.sendingStuck.errorDescription ?? ""
        #expect(stuck.contains("Quit the app and open it again, then leave"))
        #expect(!stuck.contains("in a minute"))
        let note = AssistantBootstrapper.afterWaitNote
        #expect(note(true, true) == "Your marks aren't sending. Quit the app and open it again, then leave.")
        #expect(note(true, false).contains("Check that this iPhone is online"))
        #expect(note(false, true) == "Your marks have reached your guide. You can leave now.")
    }

    @Test("Wait doesn't spin while a share call is stuck past the watchdog")
    func waitReturnsWhileStuck() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let ids = try Self.marks(1, in: stack)
        let share = StuckShare(), watchdog = ManualWatchdog()
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(),
            sleep: { _ in throw CancellationError() },
            attempt: share.attempt,
            watchdog: watchdog.sleep
        )
        attacher.attach(ids, container: stack.container, context: stack.viewContext)
        #expect(await waitUntil { share.inFlight == 1 })
        watchdog.fire()
        #expect(await waitUntil { attacher.sendingLooksStuck })

        let started = ContinuousClock.now
        let left = await AssistantBootstrapper.sendUnsentMarks(
            attacher: attacher, keepAlive: nil, syncRecord: nil, sendingStopped: false, upTo: .seconds(8)
        )
        #expect(ContinuousClock.now - started < .seconds(3), "it said so at once")
        #expect(left == .counted(1))
        share.answerAll()
        #expect(await waitUntil { !attacher.isRunning })
    }

    // MARK: - 4. A let-go call and the closed stack

    @Test("An attempt stops before its next chunk once its stack is closed or rebuilt")
    func attemptStopsOnAClosedStack() throws {
        let old = try AssistantTestSupport.makeStack(), rebuilt = try AssistantTestSupport.makeStack()
        let attemptOn = ObjectIdentifier(old.container)
        let stop = AssistantShareAttacher.stopReason
        #expect(stop(attemptOn, attemptOn, nil) == nil)
        #expect(stop(attemptOn, attemptOn, "held") == "held")
        #expect(stop(attemptOn, ObjectIdentifier(rebuilt.container), nil) == AssistantShareAttacher.stackClosedReason)
        #expect(stop(attemptOn, nil, nil) == AssistantShareAttacher.stackClosedReason)
    }

    // MARK: - 6. CloudKit's wait and the backlog

    @Test("A fresh mark refused offline during CloudKit's wait doesn't cut the wait's retry short")
    func offlineDuringCloudKitsWait() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let share = FakeShare()
        let clock = Date()
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(), now: { clock }, sleep: share.sleep, attempt: share.attempt
        )
        share.throttledFor = 300
        attacher.attach(try Self.marks(1, in: stack), container: stack.container, context: stack.viewContext)
        await attacher.waitUntilIdle()
        #expect(share.rests == [300])

        share.throttledFor = nil
        share.offline = true
        let fresh = try Self.marks(1, in: stack)
        attacher.attach(fresh, container: stack.container, context: stack.viewContext)
        await attacher.waitUntilIdle()
        #expect(share.attempts.last == fresh, "only the fresh mark went; the backlog waits")
        #expect(share.rests.last == 300, "the retry is set for the end of CloudKit's wait, not 30 s")
        #expect(attacher.backlogWaitsUntil == clock.addingTimeInterval(300))
    }

    // MARK: - 7. Wait after a relaunch

    @Test("Wait waits for the upload of a save from before a relaunch")
    func waitWaitsForAnEarlierSave() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let record = AssistantSyncRecord(viewContext: stack.viewContext, defaults: AssistantTestSupport.makeDefaults())
        let saved = Date()
        record.saved(at: saved)
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(), sleep: { _ in throw CancellationError() }
        )
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            record.record(.init(isExport: true, start: saved.addingTimeInterval(1), end: saved.addingTimeInterval(2),
                                succeeded: true))
        }
        let left = await AssistantBootstrapper.sendUnsentMarks(
            attacher: attacher, keepAlive: nil, syncRecord: record, sendingStopped: false, upTo: .seconds(8)
        )
        #expect(left == nil, "the upload began within the wait")
    }

    // MARK: - 9. A second Download from iCloud again

    @Test("A download still waiting for its membership counts as having been in a class")
    func secondDownloadStillWaits() {
        let defaults = AssistantTestSupport.makeDefaults()
        AssistantClassroomLocalState.noteShareSeen(inZone: "com.apple.coredata.cloudkit.share.ABC", defaults: defaults)

        // The first download: read, forget, remember the wait.
        #expect(AssistantClassroomLocalState.wasInAClass(defaults: defaults))
        AssistantClassroomLocalState.forget(defaults: defaults)
        AssistantClassroomLocalState.noteAwaitsMembership(defaults: defaults)
        // Its start failed again, or the app was reopened: the second still knows.
        #expect(AssistantClassroomLocalState.wasInAClass(defaults: defaults))
        #expect(AssistantClassroomLocalState.awaitsMembership(defaults: defaults))

        AssistantClassroomLocalState.membershipAwaited(defaults: defaults)
        #expect(!AssistantClassroomLocalState.wasInAClass(defaults: defaults))

        // Leave forgets it too.
        AssistantClassroomLocalState.noteAwaitsMembership(defaults: defaults)
        AssistantClassroomLocalState.forget(defaults: defaults)
        #expect(!AssistantClassroomLocalState.awaitsMembership(defaults: defaults))
    }

    // MARK: - 10. The wiring behind the rules

    @Test("Another guide's invitation is refused only while the pinned class is on this phone")
    func anotherGuideNeedsTheClassHere() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let store = try #require(stack.container.persistentStoreCoordinator.persistentStores.first)
        ClassroomRepository(context: context).createMembership(
            classroomZoneID: "com.apple.coredata.cloudkit.share.ABC", role: .assistant, ownerIdentity: "_rivera"
        )
        try context.save()
        let service = ClassroomSharingService(container: stack.container, context: context)

        #expect(!(await service.isInAnotherGuidesClass(invitedBy: "_cohen", sharedStore: store)),
                "no class here yet: nothing to mix with")
        AssistantTestSupport.student("Maya", "Stone", in: context)
        try context.save()
        #expect(await service.isInAnotherGuidesClass(invitedBy: "_cohen", sharedStore: store))
        #expect(!(await service.isInAnotherGuidesClass(invitedBy: "_rivera", sharedStore: store)),
                "the same guide's new share")
    }

    @Test("Leave's warning counts the keep-alive's unsent save and the sync record's alike")
    func unsentMarksReadsBoth() throws {
        let stack = try AssistantTestSupport.makeStack()
        let record = AssistantSyncRecord(viewContext: stack.viewContext, defaults: AssistantTestSupport.makeDefaults())
        let keepAlive = UnsentChangesKeepAlive(viewContext: stack.viewContext)
        let unsent = AssistantBootstrapper.unsentMarksNow(waitingForShare:keepAlive:syncRecord:)
        #expect(unsent(0, keepAlive, record) == nil)
        #expect(unsent(2, keepAlive, record) == .counted(2))

        let saved = Date()
        record.saved(at: saved)
        #expect(unsent(0, keepAlive, record) == .uncounted, "a save from before a relaunch")
        record.record(.init(isExport: true, start: saved.addingTimeInterval(1), end: saved.addingTimeInterval(2),
                            succeeded: true))
        #expect(unsent(0, keepAlive, record) == nil)

        AssistantTestSupport.student("Maya", "Stone", in: stack.viewContext)
        try stack.viewContext.save()
        #expect(keepAlive.hasUnsentWork)
        #expect(unsent(0, keepAlive, nil) == .uncounted, "a save this launch")
    }

    // MARK: - Helpers

    private static func marks(_ count: Int, in stack: CoreDataStack) throws -> [NSManagedObjectID] {
        let records = (0..<count).map { _ in
            let record = CDAttendanceRecord(context: stack.viewContext)
            record.id = UUID()
            return record
        }
        try stack.viewContext.save()
        return records.map(\.objectID)
    }

    private func waitUntil(upTo limit: Duration = .seconds(30), _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

/// Share calls that don't come back until the test answers them.
@MainActor
private final class StuckShare {
    private typealias Call = CheckedContinuation<CDAttendanceStore.ShareAttachResult, Never>
    private var held: [(ids: [NSManagedObjectID], call: Call)] = []

    var inFlight: Int { held.count }

    var attempt: AssistantShareAttacher.Attempt {
        { [self] ids, _, _ in
            await withCheckedContinuation { held.append((ids, $0)) }
        }
    }

    /// Every call comes back, every mark in.
    func answerAll() {
        let waiting = held
        held = []
        for call in waiting { call.call.resume(returning: .init(left: [])) }
    }
}

/// The watchdog's wait, ended when the test says.
@MainActor
private final class ManualWatchdog {
    private var fired = false

    var sleep: AssistantShareAttacher.Sleep {
        { [self] _ in
            while !fired { try await Task.sleep(for: .milliseconds(5)) }
        }
    }

    func fire() { fired = true }
}
