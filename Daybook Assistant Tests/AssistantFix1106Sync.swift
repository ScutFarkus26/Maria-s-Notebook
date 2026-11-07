import Foundation
import CoreData
import CloudKit
import Testing
@testable import Daybook_Assistant

// The sync, joining and View only findings of the 2026-11-06 Daybook
// Assistant bug hunt (docs/Reviews/Daybook Assistant bug hunt 2026-11-06.md):
// a failed setup's filing hold with nothing retrying the account check in the
// class (#5); an old View only that never cleared (#7); Leave and a rebuild
// running over each other (#8); a rebuild that closed a sheet opened during
// its ParentLocker wait (#9); and a first unlock lost while a start ran (#10).
@Suite("Daybook Assistant fixes 2026-11-06 (sync)", .serialized)
@MainActor
struct AssistantFix1106Sync {

    // MARK: - #5 The filing hold keeps asking about the account

    @Test("The account is asked again in the class too while the store's setup failed for it (#5)")
    func accountRetryRule() {
        let retries = AssistantBootstrapper.retriesAccountCheck
        #expect(retries(.couldNotDetermine, false, true))
        #expect(retries(nil, false, true))
        #expect(!retries(.couldNotDetermine, false, false), "in a class with nothing held")
        #expect(!retries(.available, false, true), "known: the rebuild decides")
        #expect(!retries(.noAccount, false, true), "a known problem waits for CKAccountChanged")
    }

    @Test("In the class, a failed setup with the account unknown is retried until it's here, then rebuilt (#5)",
          .timeLimit(.minutes(1)))
    func failedSetupRetriedInTheClass() async throws {
        let fake = try Sync1106Stacks(), account = Sync1106Account()
        fake.nextHasMembership = true
        let bootstrapper = makeBootstrapper(fake, account: account, retryDelay: .milliseconds(20))
        await bootstrapper.rebuildStack(because: "test: the first stack")
        try #require(Self.isReady(bootstrapper), "in the class")
        try #require(fake.rebuilds == 1)

        // Before: no check ran again once she was in the class, so the hold stayed.
        account.status = .couldNotDetermine
        fake.holds[0].follow(Self.failedSetup())
        #expect(await waitUntil { account.checks >= 2 }, "asked again with no one asking")
        #expect(fake.rebuilds == 1, "not while it can't tell")

        account.status = .available
        #expect(await waitUntil { fake.rebuilds == 2 && !bootstrapper.isRebuilding }, "rebuilt once it's here")
        let checks = account.checks
        try? await Task.sleep(for: .milliseconds(100))
        #expect(account.checks == checks, "the new stack holds nothing: the retries stop")
    }

    // MARK: - #7 An old View only

    @Test("A share read that says nothing drops a View only kept under the old rule, not a new one (#7)")
    func shareReadDropsTheOldAnswer() throws {
        let saved = (
            viewOnly: ClassroomPermissions.shareIsViewOnly, unconfirmed: ClassroomPermissions.viewOnlyIsUnconfirmed,
            new: UserDefaults.standard.object(forKey: ClassroomPermissions.viewOnlyKey),
            old: UserDefaults.standard.object(forKey: ClassroomPermissions.oldViewOnlyKey)
        )
        defer {
            ClassroomPermissions.shareIsViewOnly = saved.viewOnly
            ClassroomPermissions.viewOnlyIsUnconfirmed = saved.unconfirmed
            UserDefaults.standard.set(saved.new, forKey: ClassroomPermissions.viewOnlyKey)
            UserDefaults.standard.set(saved.old, forKey: ClassroomPermissions.oldViewOnlyKey)
        }
        let stack = try AssistantTestSupport.makeStack()
        ClassroomRepository(context: stack.viewContext).createMembership(
            classroomZoneID: "", role: .assistant, ownerIdentity: "unknown"
        )
        try stack.viewContext.save()
        // Carried over from the old key.
        ClassroomPermissions.shareIsViewOnly = true
        ClassroomPermissions.viewOnlyIsUnconfirmed = true
        let service = ClassroomSharingService(container: stack.container, context: stack.viewContext)
        service.loadCurrentMembership()
        #expect(service.isViewOnly)

        // Before: no word left the old answer standing, and she couldn't mark.
        service.notePermission(.unknown)
        #expect(!service.isViewOnly)
        #expect(!ClassroomPermissions.shareIsViewOnly)

        // An answer read under the new rule stands through a read that says nothing.
        service.noteViewOnly(true)
        service.notePermission(nil)
        #expect(service.isViewOnly)
        #expect(ClassroomPermissions.shareIsViewOnly)
    }

    // MARK: - #8 Leave and a rebuild

    @Test("No rebuild runs under Leave: the account's waits for it, then runs (#8)")
    func accountRebuildWaitsForLeave() async throws {
        let fake = try Sync1106Stacks(), account = Sync1106Account()
        let bootstrapper = makeBootstrapper(fake, account: account)
        await bootstrapper.rebuildStack(because: "test: the first stack")
        account.status = .noAccount
        await bootstrapper.refreshAccountStatus()
        #expect(bootstrapper.stackNeedsAccount)

        // Before: the account arriving mid-Leave rebuilt under it.
        bootstrapper.isLeavingHere = true
        account.status = .available
        await bootstrapper.refreshAccountStatus()
        #expect(fake.rebuilds == 1)
        #expect(bootstrapper.stackNeedsAccount, "kept for after Leave")
        #expect(!(await bootstrapper.rebuildStack(because: "test: any other rebuild")), "the backstop")
        #expect(fake.rebuilds == 1)

        bootstrapper.isLeavingHere = false
        await bootstrapper.refreshAccountStatus()
        #expect(fake.rebuilds == 2)
    }

    @Test("A failed setup heard during Leave is rebuilt for once Leave ends, not given up on (#8)")
    func failedSetupWaitsForLeave() async throws {
        let fake = try Sync1106Stacks(), account = Sync1106Account()
        let bootstrapper = makeBootstrapper(fake, account: account)
        await bootstrapper.rebuildStack(because: "test: the first stack")
        await bootstrapper.refreshAccountStatus()

        bootstrapper.isLeavingHere = true
        fake.holds[0].follow(Self.failedSetup())
        await bootstrapper.rebuildIfSetupFailed()
        #expect(fake.rebuilds == 1)
        #expect(bootstrapper.accountCheckAfterLeave)

        bootstrapper.isLeavingHere = false
        await bootstrapper.refreshAccountStatus()
        #expect(await waitUntil { fake.rebuilds == 2 && !bootstrapper.isRebuilding })
        #expect(fake.rebuilds == 2)
        #expect(!bootstrapper.sendingStopped, "the held-back try didn't count as a rebuild")
    }

    @Test("A mirroring stop whose rebuild Leave beat waits for Leave, then rebuilds (#8)", .timeLimit(.minutes(1)))
    func mirroringStopWaitsForLeave() async throws {
        let fake = try Sync1106Stacks(), account = Sync1106Account()
        let bootstrapper = makeBootstrapper(fake, account: account)
        await bootstrapper.rebuildStack(because: "test: the first stack")
        let first = try #require(fake.opened.first)

        // Heard while settled; Leave starts before its rebuild does.
        bootstrapper.mirroringStopped(in: first.container)
        bootstrapper.isLeavingHere = true
        #expect(await waitUntil { bootstrapper.deferredStop === first.container }, "put back to wait")
        #expect(fake.rebuilds == 1)

        // Before: the stop read as already rebuilt for, and was ignored for good.
        bootstrapper.isLeavingHere = false
        bootstrapper.settleDeferredStop()
        #expect(await waitUntil { fake.rebuilds == 2 && !bootstrapper.isRebuilding })
        #expect(!bootstrapper.sendingStopped)
    }

    @Test("Leave tapped during a rebuild waits for it, then leaves the rebuilt class (#8)", .timeLimit(.minutes(1)))
    func leaveWaitsForTheRebuild() async throws {
        let wasViewOnly = ClassroomPermissions.shareIsViewOnly
        defer { ClassroomPermissions.shareIsViewOnly = wasViewOnly }
        let fake = try Sync1106Stacks(), account = Sync1106Account()
        fake.nextHasMembership = true
        let bootstrapper = makeBootstrapper(fake, account: account)
        // The simulator's own notification center took up to a minute.
        bootstrapper.reminderCenter = FakeReminderCenter()
        await bootstrapper.rebuildStack(because: "test: the first stack")
        try #require(Self.isReady(bootstrapper))

        let rebuild = Task { await bootstrapper.rebuildStack(because: "test: mirroring stopped") }
        try #require(await waitUntil { bootstrapper.isRebuilding })
        // Before: Leave ran on the stack going away, and she was still in the class after.
        try await bootstrapper.leaveClassroom()
        _ = await rebuild.value

        #expect(fake.rebuilds == 2)
        let rebuilt = try #require(fake.opened.last)
        #expect(rebuilt.viewContext.safeFetch(CDClassroomMembership.ownRowsRequest()).isEmpty, "left the rebuilt class")
        #expect(Self.needsClassroom(bootstrapper))
    }

    // MARK: - #9 The ParentLocker wait and a sheet

    @Test("A sheet opened during the rebuild's ParentLocker wait drops the rebuild, and the sync keeps going (#9)",
          .timeLimit(.minutes(1)))
    func sheetDuringParentLockerWait() async throws {
        let fake = try Sync1106Stacks(), account = Sync1106Account(), sheet = Sync1106Flag()
        let bootstrapper = makeBootstrapper(fake, account: account)
        await bootstrapper.rebuildStack(because: "test: the first stack")
        // The rebuild's attach wait is over at once, so the sleep below ends in the send's wait.
        try #require(await AssistantShareAttacher.shared.waitUntilIdle(upTo: .seconds(10)))
        let device = FD1103Device()
        bootstrapper.parentLocker = device.sync
        let sending = Task { await device.sync.sendNow(day: device.clock.now) }
        try #require(await waitUntil { device.site.isHoldingSave })

        let rebuild = Task {
            await bootstrapper.rebuildStack(because: "test: a stall", unless: { sheet.isSet })
        }
        try #require(await waitUntil { bootstrapper.isRebuilding })
        // Past the attach wait, into the send's: the old check came before it.
        try? await Task.sleep(for: .milliseconds(300))
        #expect(bootstrapper.isRebuilding)
        // She opens the Mail composer while the send finishes.
        sheet.isSet = true
        device.site.releaseSave()
        _ = await sending.value

        // Before: asked before the wait, the rebuild went on and took the sheet down.
        #expect(!(await rebuild.value), "dropped")
        #expect(fake.rebuilds == 1)
        #expect(!device.sync.isStopped, "a dropped rebuild leaves ParentLocker running")
    }

    // MARK: - #10 An unlock during the start

    @Test("An unlock before the start ended retries a start that then fails (#10)")
    func unlockDuringStartRetries() async throws {
        let restore = try Self.noSampleOrWait()
        defer { restore() }
        let fake = try Sync1106Stacks(), account = Sync1106Account()
        fake.failsNextStarts = 1
        let bootstrapper = makeBootstrapper(fake, account: account)

        // Before: nothing had failed yet, so the unlock's retry did nothing, and
        // "Can't start" stayed until the app was killed.
        await bootstrapper.retryFailedStart()
        await bootstrapper.start()

        #expect(fake.starts == 2, "tried again once that start failed")
        #expect(Self.needsClassroom(bootstrapper))
    }

    @Test("A failed start is retried at the unlock as before, and a start that worked isn't (#10)")
    func retryAfterAFailedStart() async throws {
        let restore = try Self.noSampleOrWait()
        defer { restore() }
        let fake = try Sync1106Stacks(), account = Sync1106Account()
        fake.failsNextStarts = 1
        let bootstrapper = makeBootstrapper(fake, account: account)
        await bootstrapper.start()
        try #require(Self.isFailed(bootstrapper))

        await bootstrapper.retryFailedStart()
        #expect(fake.starts == 2)
        #expect(Self.needsClassroom(bootstrapper))
        await bootstrapper.retryFailedStart()
        #expect(fake.starts == 2)
    }

    // MARK: - Helpers

    private func makeBootstrapper(
        _ fake: Sync1106Stacks, account: Sync1106Account, retryDelay: Duration = .seconds(60)
    ) -> AssistantBootstrapper {
        AssistantBootstrapper(
            fetchAccountStatus: { account.check() },
            fetchUserRecordName: { "_assistant" },
            accountRetryDelay: retryDelay,
            stacks: fake.stacks,
            sheetIsUp: { false },
            sendsSoFar: { 0 }
        )
    }

    /// A real start reads the host's saved Sample Class and download state:
    /// neither may be set, or it opens on something other than the join screen.
    private static func noSampleOrWait() throws -> () -> Void {
        try #require(!AssistantClassroomLocalState.awaitsMembership(), "a download's wait left in the host's settings")
        let wasOpen = AssistantSampleClass.wasOpen, wasChosen = AssistantSampleClass.isChosen
        AssistantSampleClass.wasOpen = false
        AssistantSampleClass.isChosen = false
        return {
            AssistantSampleClass.wasOpen = wasOpen
            AssistantSampleClass.isChosen = wasChosen
        }
    }

    private static func failedSetup() -> AssistantFilingHold.Event {
        AssistantFilingHold.Event(
            type: .setup, succeeded: false, killedDelegate: false, start: Date(), storeIdentifier: "shared",
            accountUnavailable: true
        )
    }

    private static func isReady(_ bootstrapper: AssistantBootstrapper) -> Bool {
        if case .ready = bootstrapper.phase { true } else { false }
    }

    private static func needsClassroom(_ bootstrapper: AssistantBootstrapper) -> Bool {
        if case .needsClassroom = bootstrapper.phase { true } else { false }
    }

    private static func isFailed(_ bootstrapper: AssistantBootstrapper) -> Bool {
        if case .failed = bootstrapper.phase { true } else { false }
    }

    private func waitUntil(upTo limit: Duration = .seconds(20), _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

/// In-memory stacks a test's bootstrapper opens and rebuilds onto, each
/// with its own filing hold, as `AssistantStack` gives each its own.
@MainActor
private final class Sync1106Stacks {
    private(set) var opened: [CoreDataStack] = []
    private(set) var holds: [AssistantFilingHold] = []
    /// The next stack opened has her membership row: she's in the class.
    var nextHasMembership = false
    /// How many starts to come fail, as one before the first unlock does.
    var failsNextStarts = 0
    private(set) var starts = 0
    let sample: CoreDataStack

    init() throws {
        sample = try AssistantTestSupport.makeStack()
    }

    var rebuilds: Int { opened.count - starts + failedStarts }
    private var failedStarts = 0

    var stacks: AssistantBootstrapper.Stacks {
        AssistantBootstrapper.Stacks(
            rebuild: { [self] in try open() },
            current: { [self] in opened.last },
            filingHold: { [self] in holds.last },
            sample: { [self] in sample },
            open: { [self] in try start() },
            isOpen: { false }
        )
    }

    private func start() throws -> CoreDataStack {
        starts += 1
        if failsNextStarts > 0 {
            failsNextStarts -= 1
            failedStarts += 1
            throw CocoaError(.fileReadNoPermission)
        }
        return try open()
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

/// The account check's answer, and how many times it was asked.
@MainActor
private final class Sync1106Account {
    var status: CKAccountStatus = .available
    private(set) var checks = 0

    func check() -> CKAccountStatus {
        checks += 1
        return status
    }
}

@MainActor
private final class Sync1106Flag {
    var isSet = false
}
