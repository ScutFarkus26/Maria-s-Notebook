import Foundation
import CoreData
import CloudKit
import Testing
@testable import Daybook_Assistant

// The 2026-11-02 sync, sharing and backup hunt, the Daybook Assistant's part:
// a dead mirroring delegate found on an ordinary export held sending for the
// session with nothing said (#5); "Not in This Class" outlived a new join, and
// its Leave purged the new class (#6); a "View only" assistant could mark
// (#29); a stall rebuild ran every 10 minutes and took the screens away (#42);
// Leave counted names and Restock lines as marks (#43); marks saved before the
// share arrived waited out a long rest (#44); and Wait gave the wrong advice
// under a filing hold (#45).
@Suite("Assistant sync and sharing fixes 2026-11-02", .serialized)
@MainActor
struct AssistantSyncSharingFix1102 {

    // MARK: - #5 A dead delegate on an ordinary export

    @Test("A dead delegate on an export holds filing, rebuilds the stack once, and gives up if the new one dies too")
    func deadDelegateRebuilds() async throws {
        let fake = try RebuildStacks(), clock = Clock()
        let bootstrapper = makeBootstrapper(fake, clock)
        await bootstrapper.rebuildStack(because: "test: the first stack")
        try #require(fake.rebuilds == 1)

        // Before: the hold waited for a sync a dead delegate never makes.
        fake.holds[0].follow(Self.export(killedDelegate: true))
        #expect(fake.holds[0].wait == .mirroringDied)
        try #require(await waitUntil { fake.rebuilds == 2 && !bootstrapper.isRebuilding }, "rebuilt for the stop")
        #expect(!bootstrapper.sendingStopped)
        #expect(fake.holds[1].stopReason == nil, "the new stack starts with no hold")

        // The new stack's delegate dies too, at once: it says so, not round and round.
        fake.holds[1].follow(Self.export(killedDelegate: true))
        #expect(await waitUntil { bootstrapper.sendingStopped }, "the line says to quit and reopen")
        #expect(fake.rebuilds == 2)
    }

    @Test("The same stop heard twice for one stack rebuilds once and doesn't read as the new stack stopping")
    func stopHeardTwice() async throws {
        let fake = try RebuildStacks(), clock = Clock()
        let bootstrapper = makeBootstrapper(fake, clock)
        await bootstrapper.rebuildStack(because: "test: the first stack")
        let first = try #require(fake.opened.first)

        // The hold and the attacher can both find it.
        bootstrapper.mirroringStopped(in: first.container)
        bootstrapper.mirroringStopped(in: first.container)
        #expect(!bootstrapper.sendingStopped)
        #expect(await waitUntil { fake.rebuilds == 2 && !bootstrapper.isRebuilding })
        #expect(!bootstrapper.sendingStopped)
    }

    @Test("A held store's wait says why: iCloud not ready, or the delegate died; it lifts on a later sync")
    func holdSaysWhy() {
        let hold = AssistantFilingHold()
        let start = Date()
        hold.follow(.init(type: .setup, succeeded: false, killedDelegate: false, start: start, storeIdentifier: "s"))
        #expect(hold.wait == .iCloudNotReady)
        hold.follow(.init(type: .import, succeeded: true, killedDelegate: false,
                          start: start.addingTimeInterval(1), storeIdentifier: "s"))
        #expect(hold.wait == nil)
        let told = Count()
        hold.onMirroringDied = { told.count += 1 }
        hold.follow(Self.export(killedDelegate: true, at: start.addingTimeInterval(2)))
        hold.follow(Self.export(killedDelegate: true, at: start.addingTimeInterval(3)))
        #expect(hold.wait == .mirroringDied)
        #expect(told.count == 1, "told once a stack")
        #expect(hold.mirroringDied)
    }

    @Test("Under a filing hold the line says the marks wait for iCloud here, or for a network")
    func heldLine() {
        let usable = AssistantNetworkWatch.PathState(usable: true, interface: .wifi)
        let none = AssistantNetworkWatch.PathState(usable: false, interface: .other)
        let status = AssistantSyncStatusView.status
        // Before: "Sending to iCloud…" for good.
        #expect(status(false, 0, 0, nil, 2, false, false, usable, nil, true) == .waitingForICloud)
        #expect(status(false, 0, 0, nil, 2, false, false, nil, nil, true) == .waitingForICloud)
        // A first launch offline: setup failed for the network.
        #expect(status(false, 0, 0, nil, 2, false, false, none, nil, true) == .offline)
        // Nothing waiting: nothing to say.
        #expect(status(false, 0, 0, nil, 0, false, false, usable, nil, true) == .sent)
        #expect(status(false, 0, 0, nil, 2, false, false, usable, nil, false) == .sending)
        let words = AssistantSyncStatusView.waitingForICloudMessage
        #expect(words == "Not sent yet. iCloud isn't ready on this iPhone. Trying again.")
    }

    // MARK: - #45 Wait under a filing hold

    @Test("Wait under a filing hold says iCloud isn't ready, or to reopen when the delegate died")
    func waitUnderAHold() {
        let note = AssistantBootstrapper.afterWaitNote
        // Before: "Check that this iPhone is online", though it was.
        #expect(note(true, false, .iCloudNotReady)
            == "iCloud isn't ready on this iPhone yet, so your marks haven't gone. Wait a minute, then try again.")
        #expect(note(true, false, .mirroringDied)
            == "Your marks aren't sending. Quit the app and open it again, then leave.")
        #expect(note(true, false, nil).contains("Check that this iPhone is online"))
        #expect(note(false, false, .iCloudNotReady) == "Your marks have reached your guide. You can leave now.")
    }

    // MARK: - #6 "Not in This Class" after a new join

    @Test("Joining a class clears Not in This Class at once")
    func joinClearsRemoved() async throws {
        let fake = try RebuildStacks()
        fake.nextHasMembership = true
        let bootstrapper = makeBootstrapper(fake, Clock())
        await bootstrapper.rebuildStack(because: "test: in a class")
        bootstrapper.removedFromClass = true

        // Before: the early return for a phone already in a class left it up,
        // with a Leave that purged the new class.
        bootstrapper.joinedClassroom()
        #expect(!bootstrapper.removedFromClass)
    }

    @Test("Leave from Not in This Class purges nothing, whatever the pin names now")
    func leaveWhenRemovedPurgesNothing() throws {
        let newClass = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.share.NEW"))
        let zone = ClassroomSharingService.zoneToPurge
        #expect(try zone(true, newClass, [newClass], true) == nil, "the class was gone already")
        #expect(try zone(false, newClass, [newClass], true) == newClass.recordID.zoneID, "an ordinary Leave")
    }

    // MARK: - #42 The stall rebuild

    @Test("A stall rebuilds once a launch, again only after a send; never with a sheet up or the app unsettled")
    func stallRule() {
        let respond = AssistantBootstrapper.stallResponse
        #expect(respond(true, false, false, false, false) == .rebuild, "the first stall")
        #expect(respond(true, false, false, true, false) == .ignore, "rebuilt before, nothing sent since")
        #expect(respond(true, false, false, true, true) == .rebuild, "a send went since")
        #expect(respond(true, true, false, false, false) == .ignore, "a sheet is up")
        #expect(respond(false, false, false, false, false) == .ignore, "starting, failed, leaving or rebuilding")
        #expect(respond(true, false, true, true, true) == .ignore, "within the window")
    }

    @Test("Stalls all session rebuild once; a send lets the next one rebuild; a sheet holds it off")
    func stallsAllSession() async throws {
        let fake = try RebuildStacks(), clock = Clock(), sends = Count(), sheet = Flag()
        let bootstrapper = makeBootstrapper(fake, clock, sheetIsUp: { sheet.isSet }, sends: { sends.count })
        await bootstrapper.rebuildStack(because: "test: the first stack")

        bootstrapper.sendStalled()
        try #require(await waitUntil { fake.rebuilds == 2 && !bootstrapper.isRebuilding })
        // Before: every 10 minutes all session.
        for _ in 0..<3 {
            clock.now.addTimeInterval(AssistantBootstrapper.stallRebuildWindow + 60)
            bootstrapper.sendStalled()
            try await Task.sleep(for: .milliseconds(50))
            #expect(!bootstrapper.isRebuilding)
        }
        #expect(fake.rebuilds == 2)

        // A mark went in since: the next stall gets its rebuild, but not under a sheet.
        sends.count += 1
        sheet.isSet = true
        bootstrapper.sendStalled()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!bootstrapper.isRebuilding)
        #expect(fake.rebuilds == 2, "the Mail composer stays up")
        sheet.isSet = false
        bootstrapper.sendStalled()
        #expect(await waitUntil { fake.rebuilds == 3 && !bootstrapper.isRebuilding })
    }

    @Test("A rebuild keeps the screens up through its waits, and a sheet that came up meanwhile cancels a stall's")
    func screensStayUpThroughTheWaits() async throws {
        let fake = try RebuildStacks()
        fake.nextHasMembership = true
        let bootstrapper = makeBootstrapper(fake, Clock())
        await bootstrapper.rebuildStack(because: "test: in a class")
        let open = try #require(bootstrapper.coreDataStack)
        try #require(Self.isReady(bootstrapper))

        // Asked right before the stores would come off, after the waits.
        // Before: "Starting…" was up for the whole wait for a running attach.
        let stillUp = Flag()
        let rebuilt = await bootstrapper.rebuildStack(because: "test: stalled") {
            stillUp.isSet = bootstrapper.coreDataStack === open && Self.isReady(bootstrapper)
            return true
        }
        #expect(stillUp.isSet)
        #expect(!rebuilt)
        #expect(fake.rebuilds == 1, "left for now")
        #expect(bootstrapper.coreDataStack === open)
        #expect(Self.isReady(bootstrapper))
    }

    // MARK: - #43 What Leave counts

    @Test("Leave counts marks as marks, names not at all, and Restock and sends as other changes")
    func leaveCounts() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let mark = CDAttendanceRecord(context: context)
        mark.id = UUID()
        let name = CDClassroomPerson(context: context)
        let restock = CDSupplyTransaction(context: context)
        let send = CDAttendanceEmailSend(context: context)
        try context.save()
        let share = FakeShare()
        share.refusesEverything = true
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(), sleep: share.sleep, attempt: share.attempt
        )
        attacher.attach(
            [mark, name, restock, send].map(\.objectID), container: stack.container, context: context
        )
        await attacher.waitUntilIdle()
        let waiting = attacher.waitingByKind()
        #expect(attacher.pending.count == 4)
        // Before: "4 marks haven't reached your guide yet."
        #expect(waiting.marks == 1)
        #expect(waiting.otherChanges == 2)

        typealias Unsent = AssistantBootstrapper.UnsentMarks
        let unsent = AssistantBootstrapper.unsentMarks
        #expect(unsent(1, 2, false) == .counted(1, otherChanges: true))
        #expect(unsent(0, 2, false) == .otherChanges)
        #expect(unsent(0, 0, true) == .uncounted)
        #expect(Unsent.counted(1, otherChanges: true).message.hasPrefix(
            "1 mark and other changes haven't reached your guide yet."))
        #expect(Unsent.counted(2, otherChanges: true).message.hasPrefix(
            "2 marks and other changes haven't reached your guide yet."))
        #expect(Unsent.otherChanges.message.hasPrefix("Some of your changes haven't reached your guide yet."))
    }

    // MARK: - #44 Marks saved before the share arrived

    @Test("Marks refused for want of a share go as soon as it's found, not after the rest")
    func shareArriving() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let record = CDAttendanceRecord(context: stack.viewContext)
        record.id = UUID()
        try stack.viewContext.save()
        let share = NoShareYet()
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(), sleep: { _ in throw CancellationError() },
            attempt: share.attempt, zoneCheck: { _, _, _ in [] }
        )
        attacher.attach([record.objectID], container: stack.container, context: stack.viewContext)
        await attacher.waitUntilIdle()
        #expect(attacher.waitsForTheShare)
        #expect(attacher.pendingCount == 1)

        share.arrived = true
        // The share is read in (`readClassShare`, or a sync of the class's store).
        attacher.shareArrived()
        await attacher.waitUntilIdle()
        #expect(share.attempts == 2)
        #expect(attacher.pendingCount == 0)
        #expect(!attacher.waitsForTheShare)
        // Nothing waits for it any more: nothing more is tried.
        attacher.shareArrived()
        await attacher.waitUntilIdle()
        #expect(share.attempts == 2)
    }

    // MARK: - #29 A "View only" assistant

    @Test("The line names view only in plain words")
    func viewOnlyLine() {
        #expect(AssistantSyncStatusView.viewOnlyMessage
            == "Your guide added you to view only. Ask them to let you make changes.")
    }

    // MARK: - Helpers

    private func makeBootstrapper(
        _ fake: RebuildStacks, _ clock: Clock,
        sheetIsUp: @escaping @MainActor () -> Bool = { false },
        sends: @escaping @MainActor () -> Int = { 0 }
    ) -> AssistantBootstrapper {
        AssistantBootstrapper(
            fetchAccountStatus: { .available },
            fetchUserRecordName: { "_assistant" },
            accountRetryDelay: .seconds(60),
            stacks: fake.stacks,
            now: { clock.now },
            sheetIsUp: sheetIsUp,
            sendsSoFar: sends
        )
    }

    private static func export(killedDelegate: Bool, at start: Date = Date()) -> AssistantFilingHold.Event {
        AssistantFilingHold.Event(
            type: .export, succeeded: false, killedDelegate: killedDelegate, start: start, storeIdentifier: "shared"
        )
    }

    private static func isReady(_ bootstrapper: AssistantBootstrapper) -> Bool {
        if case .ready = bootstrapper.phase { true } else { false }
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

/// In-memory stacks a test's bootstrapper rebuilds onto, each with its own
/// filing hold, as `AssistantStack` gives each rebuilt stack its own.
@MainActor
private final class RebuildStacks {
    private(set) var opened: [CoreDataStack] = []
    private(set) var holds: [AssistantFilingHold] = []
    /// The next stack opened has her membership row: she's in the class.
    var nextHasMembership = false
    let sample: CoreDataStack

    init() throws {
        sample = try AssistantTestSupport.makeStack()
    }

    var rebuilds: Int { opened.count }

    var stacks: AssistantBootstrapper.Stacks {
        AssistantBootstrapper.Stacks(
            rebuild: { [self] in try open() },
            current: { [self] in opened.last },
            filingHold: { [self] in holds.last },
            sample: { [self] in sample }
        )
    }

    private func open() throws -> CoreDataStack {
        let stack = try AssistantTestSupport.makeStack()
        if nextHasMembership {
            ClassroomRepository(context: stack.viewContext).createMembership(
                classroomZoneID: "", role: .assistant, ownerIdentity: "unknown"
            )
            try stack.viewContext.save()
        }
        opened.append(stack)
        holds.append(AssistantFilingHold())
        return stack
    }
}

/// The classroom share before it has arrived on the phone: every record is
/// left for want of it, until `arrived`.
@MainActor
private final class NoShareYet {
    var arrived = false
    private(set) var attempts = 0

    var attempt: AssistantShareAttacher.Attempt {
        { [self] ids, _, _ in
            attempts += 1
            return arrived ? .init(left: []) : .init(left: ids, noShare: true)
        }
    }
}

@MainActor
private final class Clock {
    var now = Date()
}

@MainActor
private final class Count {
    var count = 0
}

@MainActor
private final class Flag {
    var isSet = false
}
