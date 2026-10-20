import Foundation
import CoreData
import CloudKit
import Testing
@testable import Daybook_Assistant

// The review of the 2026-10-20 sync and joining fixes (review b), the
// rebuilds and joins: the stack rebuilt for the account couldn't be rebuilt
// for its own failed setup (item 1); a slow join was lost under a rebuild (2);
// a rebuild while the Sample Class was open skipped becoming ready, or opened
// the class on the stack about to close (5); and the wiring behind those
// rules (10). The sending items are in AssistantSendingFix1020RoundB.
@Suite("Assistant rebuild and join review fixes 2026-10-20", .serialized)
@MainActor
struct AssistantSyncFix1020RoundB {

    // MARK: - 1. The class store's failed setup

    @Test("The stack rebuilt for the account gets its own rebuild when its setup fails too; then it gives up")
    func rebuiltStacksOwnFailedSetup() async throws {
        let fake = try FakeStacks(), clock = TestClock(), account = AccountAnswer()
        let bootstrapper = makeBootstrapper(fake, clock, account)
        await bootstrapper.rebuildStack(because: "test: the first stack")
        #expect(fake.rebuilds == 1)

        // Built without an account; then it arrives.
        account.status = .noAccount
        await bootstrapper.refreshAccountStatus()
        account.status = .available
        await bootstrapper.refreshAccountStatus()
        try #require(fake.rebuilds == 2, "rebuilt for the account")

        // The rebuilt stack's setup fails for the account while it settles.
        fake.holds[1].follow(Self.failedSetup())
        try #require(await waitUntil { fake.rebuilds == 3 && !bootstrapper.isRebuilding }, "its own rebuild")
        #expect(!bootstrapper.sendingStopped)

        // That one fails too, at once: no rebuilding round and round.
        fake.holds[2].follow(Self.failedSetup())
        #expect(await waitUntil { bootstrapper.sendingStopped }, "the line says to quit and reopen")
        #expect(fake.rebuilds == 3)

        // Long after, a check finds the setup still failed: rebuilt again.
        clock.now.addTimeInterval(AssistantBootstrapper.failedSetupRebuildWindow + 60)
        await bootstrapper.refreshAccountStatus()
        #expect(fake.rebuilds == 4)
        #expect(!bootstrapper.sendingStopped)
    }

    @Test("A failed setup heard while a rebuild still runs gets its rebuild when that one ends")
    func failedSetupDuringRebuild() async throws {
        let fake = try FakeStacks(), clock = TestClock(), account = AccountAnswer()
        let bootstrapper = makeBootstrapper(fake, clock, account)
        let wasOpen = AssistantSampleClass.wasOpen, wasChosen = AssistantSampleClass.isChosen
        defer {
            AssistantSampleClass.wasOpen = wasOpen
            AssistantSampleClass.isChosen = wasChosen
        }
        await bootstrapper.rebuildStack(because: "test: the first stack")
        await bootstrapper.refreshAccountStatus()
        bootstrapper.openSampleClass()
        #expect(fake.rebuilds == 1)

        // Mirroring stopped: a rebuild runs under the sample, and the old
        // stack's setup failure is heard meanwhile.
        let rebuild = Task { await bootstrapper.rebuildStack(because: "test: mirroring stopped") }
        #expect(await waitUntil { bootstrapper.isRebuilding })
        fake.holds[0].follow(Self.failedSetup())
        await rebuild.value
        #expect(await waitUntil { !bootstrapper.isRebuilding })
        try #require(fake.rebuilds == 2)

        // The rebuilt stack's own setup fails: it still gets its rebuild.
        fake.holds[1].follow(Self.failedSetup())
        #expect(await waitUntil { fake.rebuilds == 3 && !bootstrapper.isRebuilding }, "not spent on the running one")
        #expect(!bootstrapper.sendingStopped)
    }

    // MARK: - 2. A join under way

    @Test("A join's own timeout leaves the decision to a rebuild waiting for it")
    func joinTimeoutDefersToTheRebuild() throws {
        let stack = try AssistantTestSupport.makeStack()
        let service = ClassroomSharingService(container: stack.container, context: stack.viewContext)
        service.keepsFailedInvitation = true
        let attempt = service.beginJoin()
        service.joinTimedOut(attempt)
        #expect(service.isJoining, "still joining while the rebuild waits")
        #expect(service.shareError == nil)

        service.keepsFailedInvitation = false
        service.joinTimedOut(attempt)
        #expect(!service.isJoining)
        #expect(service.acceptIsRunning, "the accept itself still runs")
        #expect(service.shareError == ClassroomSharingService.joinTimeoutMessage)
    }

    @Test("The rebuild waits for an accept that timed out on screen")
    func rebuildWaitsForATimedOutAccept() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let service = ClassroomSharingService(container: stack.container, context: stack.viewContext)
        let bootstrapper = AssistantBootstrapper(stacks: try FakeStacks().stacks)
        let attempt = service.beginJoin()
        service.joinTimedOut(attempt)
        #expect(!service.isJoining)

        let answered = Flag()
        let wait = Task { () -> Bool in
            _ = await bootstrapper.waitForJoinBeforeRebuild(on: service, upTo: .seconds(10))
            return answered.isSet
        }
        try await Task.sleep(for: .milliseconds(150))
        answered.isSet = true
        service.endJoin(attempt)
        #expect(await wait.value, "it returned once the accept came back, not before")
    }

    @Test("A join a rebuilt stack took over says nothing when its old accept fails late")
    func letGoJoinIsSilent() throws {
        let stack = try AssistantTestSupport.makeStack()
        let service = ClassroomSharingService(container: stack.container, context: stack.viewContext)
        let attempt = service.beginJoin()
        service.letGoOfJoin()
        #expect(!service.isJoining)
        #expect(!service.acceptIsRunning)
        service.joinFailed(CKError(.networkFailure), invitation: nil, attempt: attempt)
        service.endJoin(attempt)
        service.joinTimedOut(attempt)
        #expect(service.shareError == nil)
    }

    // MARK: - 5. A rebuild while the Sample Class is open

    @Test("A rebuild over the Sample Class: a class that arrived underneath goes through becoming ready")
    func rebuildOverTheSampleBecomesReady() async throws {
        let fake = try FakeStacks()
        let bootstrapper = makeBootstrapper(fake, TestClock(), AccountAnswer())
        let wasOpen = AssistantSampleClass.wasOpen, wasChosen = AssistantSampleClass.isChosen
        defer {
            AssistantSampleClass.wasOpen = wasOpen
            AssistantSampleClass.isChosen = wasChosen
        }
        await bootstrapper.rebuildStack(because: "test: the first stack")
        bootstrapper.openSampleClass()
        #expect(AssistantSampleClass.isChosen)

        fake.nextHasMembership = true
        await bootstrapper.rebuildStack(because: "test: the account arrived")
        #expect(bootstrapper.coreDataStack === fake.opened.last)
        #expect(Self.isReady(bootstrapper))
        #expect(bootstrapper.timesBecameReady == 1, "the guide's name, waiting marks and removed check")
        #expect(!AssistantSampleClass.isChosen)
        #expect(!AssistantSampleClass.wasOpen)
    }

    @Test("The class arriving mid-rebuild over the Sample Class opens on the new stack, not the closing one")
    func classArrivingMidRebuild() async throws {
        let fake = try FakeStacks()
        let bootstrapper = makeBootstrapper(fake, TestClock(), AccountAnswer())
        let wasOpen = AssistantSampleClass.wasOpen, wasChosen = AssistantSampleClass.isChosen
        defer {
            AssistantSampleClass.wasOpen = wasOpen
            AssistantSampleClass.isChosen = wasChosen
        }
        await bootstrapper.rebuildStack(because: "test: the first stack")
        bootstrapper.openSampleClass()
        fake.nextHasMembership = true

        let rebuild = Task { await bootstrapper.rebuildStack(because: "test: mirroring stopped") }
        #expect(await waitUntil { bootstrapper.isRebuilding })
        #expect(fake.rebuilds == 1, "still waiting before the stores come off")
        // An import brings the class under the sample (`followRemoteChange`).
        bootstrapper.leaveSampleClass()
        #expect(bootstrapper.coreDataStack == nil, "not the stack about to be closed")

        await rebuild.value
        #expect(fake.rebuilds == 2)
        #expect(bootstrapper.coreDataStack === fake.opened.last)
        #expect(Self.isReady(bootstrapper))
        #expect(bootstrapper.timesBecameReady == 1)
    }

    @Test("A rebuild reopens the Sample Class on the join screen, and not once a class arrived")
    func rebuildResumesTheSample() async throws {
        let fake = try FakeStacks()
        let bootstrapper = makeBootstrapper(fake, TestClock(), AccountAnswer())
        let wasOpen = AssistantSampleClass.wasOpen, wasChosen = AssistantSampleClass.isChosen
        defer {
            AssistantSampleClass.wasOpen = wasOpen
            AssistantSampleClass.isChosen = wasChosen
        }
        AssistantSampleClass.isChosen = false
        AssistantSampleClass.wasOpen = true
        await bootstrapper.rebuildStack(because: "test: the first stack")
        #expect(AssistantSampleClass.isChosen)
        #expect(bootstrapper.coreDataStack === fake.sample)

        fake.nextHasMembership = true
        await bootstrapper.rebuildStack(because: "test: the class arrived")
        #expect(!AssistantSampleClass.isChosen)
        #expect(!AssistantSampleClass.wasOpen)
        #expect(bootstrapper.coreDataStack === fake.opened.last)
        #expect(Self.isReady(bootstrapper))
    }

    // MARK: - Helpers

    private func makeBootstrapper(
        _ fake: FakeStacks, _ clock: TestClock, _ account: AccountAnswer
    ) -> AssistantBootstrapper {
        AssistantBootstrapper(
            fetchAccountStatus: { account.status },
            fetchUserRecordName: { "_assistant" },
            accountRetryDelay: .seconds(60),
            stacks: fake.stacks,
            now: { clock.now }
        )
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
private final class FakeStacks {
    private(set) var opened: [CoreDataStack] = []
    private(set) var holds: [AssistantFilingHold] = []
    /// The next stack opened has her membership row: the class arrived.
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

@MainActor
private final class TestClock {
    var now = Date()
}

@MainActor
private final class AccountAnswer {
    var status: CKAccountStatus = .available
}

@MainActor
private final class Flag {
    var isSet = false
}
