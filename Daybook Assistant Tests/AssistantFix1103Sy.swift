import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Daybook Assistant bugs and efficiency hunt 2026-11-03, sync (#2, #9, #10,
// #13, #15): the filing hold lifted on a container that can't share; a
// rebuilt stack forgot the keep-alive's unsent edits; a share call stuck past
// the watchdog kept every lock awake and left a task waiting on it; one
// waiter's timer ended every wait for an export.
@Suite("Assistant sync fixes 2026-11-03", .serialized)
@MainActor
struct AssistantFix1103Sy {

    // MARK: - #2 The hold on a container that can't share

    @Test("After a setup that failed for the account, an import doesn't lift the hold")
    func accountFailureKeepsTheHold() {
        let hold = AssistantFilingHold()
        let lifts = Count()
        hold.onLift = { lifts.count += 1 }
        let failedAt = Date()
        let noAccount = NSError(domain: NSCocoaErrorDomain, code: 134_400)
        hold.follow(.init(
            type: .setup, succeeded: false, killedDelegate: false, start: failedAt, storeIdentifier: "shared",
            accountUnavailable: AssistantFilingHold.isAccountUnavailable(noAccount)
        ))
        #expect(hold.setupFailedForAccount)

        // The account arrives and an import works; sharing still can't.
        hold.follow(.init(
            type: .import, succeeded: true, killedDelegate: false,
            start: failedAt.addingTimeInterval(1), storeIdentifier: "shared"
        ))
        #expect(hold.stopReason == AssistantFilingHold.reason, "the marks wait for the rebuilt stack")
        #expect(hold.wait == .iCloudNotReady)
        #expect(lifts.count == 0, "nothing is sent into this container")
    }

    @Test("After the delegate died, a sync that works doesn't lift the hold")
    func deadDelegateKeepsTheHold() {
        let hold = AssistantFilingHold()
        let lifts = Count()
        hold.onLift = { lifts.count += 1 }
        let start = Date()
        hold.follow(.init(type: .export, succeeded: false, killedDelegate: true, start: start, storeIdentifier: "s"))
        hold.follow(.init(
            type: .import, succeeded: true, killedDelegate: false,
            start: start.addingTimeInterval(1), storeIdentifier: "s"
        ))
        #expect(hold.stopReason != nil)
        #expect(hold.wait == .mirroringDied)
        #expect(lifts.count == 0)
    }

    // MARK: - #9 The keep-alive across a rebuild

    @Test("A rebuilt stack's keep-alive takes over the old one's unsent edits, for stores still open")
    func keepAliveHandOver() throws {
        let stack = try AssistantTestSupport.makeStack()
        let old = UnsentChangesKeepAlive(viewContext: stack.viewContext)
        try Self.editAMark(in: stack)
        let since = try #require(old.unsentSince)
        let stores = Set(stack.container.persistentStoreCoordinator.persistentStores.compactMap(\.identifier))

        let rebuilt = UnsentChangesKeepAlive(viewContext: stack.viewContext)
        #expect(!rebuilt.hasUnsentWork, "before: a rebuilt stack's started empty")
        rebuilt.takeUnsent(from: old, stores: stores)
        #expect(rebuilt.unsentSince == since)
        #expect(rebuilt.needsKeepAlive, "locking now keeps the phone awake for it")
        rebuilt.exported(startedAt: Date())
        #expect(!rebuilt.hasUnsentWork)

        let deleted = UnsentChangesKeepAlive(viewContext: stack.viewContext)
        deleted.takeUnsent(from: old, stores: [])
        #expect(!deleted.hasUnsentWork, "a store that didn't come back has nothing left to send")
    }

    // MARK: - #10 A share call stuck past the watchdog

    @Test("Once a share call looks stuck, the attacher isn't busy and waiting for it returns", .timeLimit(.minutes(1)))
    func idleWaitEndsWhenStuck() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let share = HeldShare(), watchdog = FiredWatchdog()
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(),
            sleep: { _ in throw CancellationError() },
            attempt: share.attempt,
            watchdog: watchdog.sleep,
            networkUsable: { nil }
        )
        attacher.attach(try Self.marks(1, in: stack), container: stack.container, context: stack.viewContext)
        #expect(await waitUntil { share.inFlight == 1 })
        #expect(attacher.isBusy)
        watchdog.fire()
        #expect(await waitUntil { attacher.sendingLooksStuck })
        #expect(!attacher.isBusy, "locking doesn't keep the phone awake for a call that may never return")

        // Before: it waited on the stuck call, and each lock of the phone
        // left one more task waiting with it.
        let returned = await UnsentChangesKeepAlive.wait(atMost: .seconds(3)) { await attacher.waitUntilIdle() }
        #expect(returned)
        #expect(attacher.isRunning, "the call itself carries on")

        share.answerAll()
        #expect(await waitUntil { !attacher.isRunning })
        #expect(attacher.pending.isEmpty)
    }

    @Test("A cancelled bounded wait for the attacher returns at once rather than spinning", .timeLimit(.minutes(1)))
    func cancelledBoundedWait() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let share = HeldShare()
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(),
            sleep: { _ in throw CancellationError() },
            attempt: share.attempt,
            networkUsable: { nil }
        )
        attacher.attach(try Self.marks(1, in: stack), container: stack.container, context: stack.viewContext)
        #expect(await waitUntil { share.inFlight == 1 })

        let waiting = Task { @MainActor in
            let started = ContinuousClock.now
            let idle = await attacher.waitUntilIdle(upTo: .seconds(3))
            return (idle, ContinuousClock.now - started)
        }
        waiting.cancel()
        let (idle, took) = await waiting.value
        #expect(!idle, "the pass still runs")
        #expect(took < .seconds(1))

        share.answerAll()
        #expect(await waitUntil { !attacher.isRunning })
    }

    // MARK: - #13 Two waits for one export

    @Test("A short wait for the export ends only itself; a longer one waits on", .timeLimit(.minutes(1)))
    func eachWaitHasItsOwnDeadline() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let keepAlive = UnsentChangesKeepAlive(
            viewContext: stack.viewContext,
            sleep: { limit in
                // The short wait's limit passes at once; the long one's never does here.
                guard limit > .seconds(1) else { return }
                try await Task.sleep(for: .seconds(60))
            }
        )
        try Self.editAMark(in: stack)
        #expect(keepAlive.hasUnsentWork)

        let long = Finished()
        let longWait = Task { @MainActor in
            await keepAlive.waitUntilSent(upTo: .seconds(25))
            long.value = true
        }
        try await Task.sleep(for: .milliseconds(50))
        await keepAlive.waitUntilSent(upTo: .milliseconds(10))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!long.value, "Leave's wait isn't cut short by a lock's")

        keepAlive.exported(startedAt: Date())
        await longWait.value
        #expect(long.value)
    }

    // MARK: - #15 Smaller

    @Test("Fetch requests name the same entities from the cached map")
    func entityNamesFromTheMap() {
        #expect(CDFetchRequest(CDAttendanceRecord.self).entityName == "AttendanceRecord")
        #expect(CDFetchRequest(CDStudent.self).entityName == "Student")
        #expect(CDFetchRequest(CDAttendanceRecord.self).entityName == "AttendanceRecord", "again, from the map")
    }

    @Test("An import that can't bring name rows is noted without looking at them")
    func importWithoutNames() throws {
        let stack = try AssistantTestSupport.makeStack()
        let arrival = ClassroomNames.Arrival(waitsForTheClass: true)
        let row = CDClassroomPerson(context: stack.viewContext)
        row.id = UUID()
        try stack.viewContext.save()
        arrival.zonesContext = stack.viewContext
        let start = Date()
        arrival.noteImport(intoStoreWithIdentifier: "private", startedAt: start, mayBringNames: false)
        #expect(arrival.importStarts["private"] == start)
        #expect(arrival.importWork == nil, "no warm-up for rows this import couldn't have brought")
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

    /// A change to a mark already there: what the upload carries.
    private static func editAMark(in stack: CoreDataStack) throws {
        let record = CDAttendanceRecord(context: stack.viewContext)
        record.id = UUID()
        try stack.viewContext.save()
        record.note = "Early pickup"
        try stack.viewContext.save()
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

@MainActor
private final class Count {
    var count = 0
}

@MainActor
private final class Finished {
    var value = false
}

/// Share calls that don't come back until the test answers them.
@MainActor
private final class HeldShare {
    private typealias Call = CheckedContinuation<CDAttendanceStore.ShareAttachResult, Never>
    private var held: [Call] = []

    var inFlight: Int { held.count }

    var attempt: AssistantShareAttacher.Attempt {
        { [self] _, _, _ in
            await withCheckedContinuation { held.append($0) }
        }
    }

    /// Every call comes back, every mark in.
    func answerAll() {
        let waiting = held
        held = []
        for call in waiting { call.resume(returning: .init(left: [])) }
    }
}

/// The watchdog's wait, ended when the test says.
@MainActor
private final class FiredWatchdog {
    private var fired = false

    var sleep: AssistantShareAttacher.Sleep {
        { [self] _ in
            while !fired { try await Task.sleep(for: .milliseconds(5)) }
        }
    }

    func fire() { fired = true }
}
