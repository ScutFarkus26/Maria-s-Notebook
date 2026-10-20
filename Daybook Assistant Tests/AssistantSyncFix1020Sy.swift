import Foundation
import CoreData
import CloudKit
import Testing
@testable import Daybook_Assistant

// Bug hunt 2026-10-20, sync and joining (#7, #13, #21, #25): a share call
// that never came back held every later mark, a rebuilt stack still waited on
// it, and its late answer could have been taken for the new pass's; a hold's
// release set no retry while CloudKit asked to wait; a mirroring stop found
// before anyone listened went unheard; the Sample Class stayed up over a
// join; a failed first account check spun until the app came back.
@Suite("Assistant sync and joining fixes 2026-10-20")
@MainActor
struct AssistantSyncFix1020Sy {

    private let defaults = AssistantTestSupport.makeDefaults()

    // MARK: - #7 The watchdog

    @Test("A call past the watchdog says so; a rebuilt stack starts a new pass; the old call's answer is dropped")
    func stuckCallRebuiltThenAnswers() async throws {
        let files = try StackFiles()
        defer { files.remove() }
        let old = try files.open()
        let ids = try Self.marks(2, in: old)
        let share = HangingShare(), watchdog = Watchdog()
        let attacher = launch(share, watchdog)

        attacher.attach(ids, container: old.container, context: old.viewContext)
        #expect(await waitUntil { share.inFlight == 1 })
        #expect(!attacher.sendingLooksStuck)
        watchdog.fire()
        #expect(await waitUntil(upTo: .seconds(3)) { attacher.sendingLooksStuck }, "the line says to quit and reopen")

        // The account arrives: the stack is rebuilt on the same files.
        let rebuilt = try files.rebuild(old)
        attacher.flush(container: rebuilt.container, context: rebuilt.viewContext)
        #expect(await waitUntil(upTo: .seconds(3)) { share.attempts.count == 2 }, "a new pass runs")
        #expect(share.contexts.last === rebuilt.viewContext)
        #expect(!attacher.sendingLooksStuck)

        // The old call comes back, however late, saying all went in.
        share.answer(1)
        try await Task.sleep(for: .milliseconds(100))
        #expect(share.attempts.count == 2, "the old pass doesn't go round again")
        #expect(share.inFlight == 1, "only the new pass's call is in flight")
        #expect(attacher.pending.count == 2, "its answer is dropped: the marks wait for the new pass")
        #expect(attacher.isRunning)

        share.answer(2)
        #expect(await waitUntil(upTo: .seconds(3)) { !attacher.isRunning })
        #expect(attacher.pending.isEmpty)
        #expect(share.attempts.count == 2)
    }

    @Test("Rebuilt first, the stuck pass is let go of when the watchdog fires")
    func rebuiltThenWatchdog() async throws {
        let files = try StackFiles()
        defer { files.remove() }
        let old = try files.open()
        let ids = try Self.marks(1, in: old)
        let share = HangingShare(), watchdog = Watchdog()
        let attacher = launch(share, watchdog)

        attacher.attach(ids, container: old.container, context: old.viewContext)
        #expect(await waitUntil { share.inFlight == 1 })
        let rebuilt = try files.rebuild(old)
        attacher.flush(container: rebuilt.container, context: rebuilt.viewContext)
        try await Task.sleep(for: .milliseconds(50))
        #expect(share.attempts.count == 1, "under the limit, the pass is waited for")

        watchdog.fire()
        #expect(await waitUntil(upTo: .seconds(3)) { share.attempts.count == 2 })
        #expect(share.contexts.last === rebuilt.viewContext)
        share.answer(2)
        share.answer(1, refusing: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await waitUntil(upTo: .seconds(3)) { !attacher.isRunning })
        #expect(attacher.pending.isEmpty, "the old call's refusal doesn't put the marks back")
        #expect(share.attempts.count == 2)
    }

    @Test("A slow call on the same stack: the line says so until it comes back, and its answer counts")
    func slowCallComesBack() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let ids = try Self.marks(1, in: stack)
        let share = HangingShare(), watchdog = Watchdog()
        let attacher = launch(share, watchdog)

        attacher.attach(ids, container: stack.container, context: stack.viewContext)
        #expect(await waitUntil { share.inFlight == 1 })
        watchdog.fire()
        #expect(await waitUntil(upTo: .seconds(3)) { attacher.sendingLooksStuck })
        // The same stack: nothing new starts; a save only asks for another round.
        attacher.flush(container: stack.container, context: stack.viewContext)
        try await Task.sleep(for: .milliseconds(50))
        #expect(share.attempts.count == 1)

        share.answer(1)
        #expect(await waitUntil(upTo: .seconds(3)) { !attacher.isRunning })
        #expect(!attacher.sendingLooksStuck)
        #expect(attacher.pending.isEmpty)
    }

    // MARK: - #13 The hold, and an unheard stop

    @Test("Releasing a hold while CloudKit asked to wait sets the backlog's retry again")
    func releaseRearmsTheRetry() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let ids = try Self.marks(1, in: stack)
        let share = FakeShare()
        let clock = Date()
        let attacher = AssistantShareAttacher(
            defaults: defaults, now: { clock }, sleep: share.sleep, attempt: share.attempt
        )
        share.throttledFor = 300
        attacher.attach(ids, container: stack.container, context: stack.viewContext)
        await attacher.waitUntilIdle()
        #expect(await waitUntil { share.rests.count == 1 })
        #expect(share.rests == [300])

        // Leave or a rebuild holds the queue, which cancels the retry.
        attacher.hold()
        attacher.release()
        await attacher.waitUntilIdle()
        #expect(await waitUntil(upTo: .seconds(2)) { share.rests.count == 2 }, "a retry is set again")
        #expect(share.rests.last == 300)
        #expect(share.attempts.count == 1, "the backlog isn't tried before CloudKit's wait ends")
    }

    @Test("A mirroring stop found before anyone listened is told to the first listener")
    func unheardStopIsTold() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let ids = try Self.marks(1, in: stack)
        let share = FakeShare()
        let attacher = AssistantShareAttacher(defaults: defaults, sleep: share.sleep, attempt: share.attempt)
        share.stopsMirroringNextAttempt = true
        attacher.attach(ids, container: stack.container, context: stack.viewContext)
        await attacher.waitUntilIdle()

        let told = ToldStops()
        attacher.onMirroringStopped = { told.containers.append($0) }
        #expect(told.containers.count == 1)
        #expect(told.containers.first === stack.container)
        // Told once.
        attacher.onMirroringStopped = { told.containers.append($0) }
        #expect(told.containers.count == 1)
    }

    // MARK: - #25 The first account check

    @Test("A failed account check asks again on its own while the join screen may show")
    func failedAccountCheckRetries() async {
        let account = FlakyAccount(answers: [nil, .couldNotDetermine, .available])
        let bootstrapper = AssistantBootstrapper(
            fetchAccountStatus: { try account.next() }, accountRetryDelay: .milliseconds(20)
        )
        await bootstrapper.refreshAccountStatus()
        #expect(bootstrapper.accountStatus == nil)
        #expect(await waitUntil(upTo: .seconds(3)) { bootstrapper.accountStatus == .available })
        #expect(account.calls == 3, "can't tell is asked again too")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(account.calls == 3, "an answer stops the asking")
    }

    // MARK: - #21 An invitation over the Sample Class

    @Test("An invitation arriving while the Sample Class is open leaves it for the join screen")
    func invitationLeavesTheSample() async {
        let bootstrapper = AssistantBootstrapper()
        bootstrapper.observeAcceptance()
        let wasChosen = AssistantSampleClass.isChosen, wasOpen = AssistantSampleClass.wasOpen
        defer {
            AssistantSampleClass.isChosen = wasChosen
            AssistantSampleClass.wasOpen = wasOpen
        }
        AssistantSampleClass.isChosen = true
        AssistantSampleClass.wasOpen = true
        NotificationCenter.default.post(name: .didAcceptCloudKitShare, object: nil)
        #expect(await waitUntil(upTo: .seconds(2)) { !AssistantSampleClass.isChosen })
        #expect(!AssistantSampleClass.wasOpen, "a relaunch doesn't reopen it over the join")
        let onJoinScreen = if case .needsClassroom = bootstrapper.phase { true } else { false }
        #expect(onJoinScreen)
    }

    // MARK: - Helpers

    private func launch(_ share: HangingShare, _ watchdog: Watchdog) -> AssistantShareAttacher {
        AssistantShareAttacher(
            defaults: defaults,
            sleep: { _ in throw CancellationError() },
            attempt: share.attempt,
            watchdog: watchdog.sleep
        )
    }

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

/// A store on disk, so a rebuilt stack opens the same files and reads the
/// same marks, as `AssistantStack.rebuild` does.
@MainActor
private final class StackFiles {
    let url: URL
    private var opened: [CoreDataStack] = []

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fix1020Sy-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("private.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func open() throws -> CoreDataStack {
        let stack = try CoreDataStack(enableCloudKit: false, localStoreURL: url)
        opened.append(stack)
        return stack
    }

    /// The old stack's stores come off, and a new stack opens the files.
    func rebuild(_ old: CoreDataStack) throws -> CoreDataStack {
        Self.close(old)
        return try open()
    }

    /// Every stack's stores come off before the files go.
    func remove() {
        opened.forEach(Self.close)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private static func close(_ stack: CoreDataStack) {
        let coordinator = stack.container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try? coordinator.remove(store) }
    }
}

/// Share calls that don't come back until the test answers them, by number
/// (the first call is 1), the way a hung `share(_:to:)` doesn't.
@MainActor
private final class HangingShare {
    private(set) var attempts: [[NSManagedObjectID]] = []
    private(set) var contexts: [NSManagedObjectContext] = []
    private typealias Call = CheckedContinuation<CDAttendanceStore.ShareAttachResult, Never>
    private var held: [Int: (ids: [NSManagedObjectID], call: Call)] = [:]

    var inFlight: Int { held.count }

    var attempt: AssistantShareAttacher.Attempt {
        { [self] ids, _, context in
            attempts.append(ids)
            contexts.append(context)
            let number = attempts.count
            return await withCheckedContinuation { held[number] = (ids, $0) }
        }
    }

    /// Call `number` comes back: every mark in, or every one refused.
    func answer(_ number: Int, refusing: Bool = false) {
        guard let waiting = held.removeValue(forKey: number) else { return }
        waiting.call.resume(returning: .init(left: refusing ? waiting.ids : []))
    }
}

/// The watchdog's wait, ended when the test says: `fire()` ends every wait
/// begun so far, and a cancelled one ends as the real sleep does.
@MainActor
private final class Watchdog {
    private var begun = 0
    private var firedThrough = 0

    var sleep: AssistantShareAttacher.Sleep {
        { [self] _ in
            begun += 1
            let mine = begun
            while firedThrough < mine { try await Task.sleep(for: .milliseconds(5)) }
        }
    }

    func fire() { firedThrough = begun }
}

/// The containers a mirroring stop was told for.
@MainActor
private final class ToldStops {
    var containers: [NSPersistentCloudKitContainer] = []
}

/// Account checks answered in turn: nil is a check that fails.
@MainActor
private final class FlakyAccount {
    private var answers: [CKAccountStatus?]
    private(set) var calls = 0

    init(answers: [CKAccountStatus?]) { self.answers = answers }

    func next() throws -> CKAccountStatus {
        calls += 1
        let answer = answers.isEmpty ? .available : answers.removeFirst()
        guard let answer else { throw CKError(.networkFailure) }
        return answer
    }
}
