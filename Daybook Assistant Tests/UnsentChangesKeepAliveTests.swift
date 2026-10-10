import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// What leaving the foreground waits for, on an in-memory stack. CloudKit's
// export events can't be made in a test, so they're reported through
// `exported(startedAt:)`, which is all the event observer does.
@Suite("Unsent changes keep-alive")
@MainActor
struct UnsentChangesKeepAliveTests {

    private let stack: CoreDataStack

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    private func saveAMark() {
        let record = CDAttendanceRecord(context: context)
        record.id = UUID()
        #expect(context.safeSave())
    }

    @Test("A save is unsent until an export that started after it finishes")
    func exportAfterTheSave() throws {
        let keepAlive = UnsentChangesKeepAlive(viewContext: context)
        #expect(!keepAlive.hasUnsentWork)

        saveAMark()
        let since = try #require(keepAlive.unsentSince)
        #expect(keepAlive.hasUnsentWork)

        // An export already running when she tapped doesn't hold the mark.
        keepAlive.exported(startedAt: since.addingTimeInterval(-1))
        #expect(keepAlive.hasUnsentWork)

        keepAlive.exported(startedAt: Date())
        #expect(!keepAlive.hasUnsentWork)
    }

    @Test("A save with nothing in it leaves nothing unsent")
    func emptySave() {
        let keepAlive = UnsentChangesKeepAlive(viewContext: context)
        #expect(context.safeSave())
        #expect(!keepAlive.hasUnsentWork)
    }

    // Sync and sharing bug hunt 2026-10-05, #8. Only the first save was
    // kept: she marks A, an upload starts, she marks B, the upload
    // finishes, and it counted as covering both. Leave's Wait then said her
    // marks had reached the guide and removed the class, B included.
    @Test("An export that began between two saves leaves the second unsent")
    func newestSaveCounts() async throws {
        let keepAlive = UnsentChangesKeepAlive(viewContext: context)
        saveAMark()
        let first = try #require(keepAlive.unsentSince)
        try await Task.sleep(for: .milliseconds(10))
        let uploadStarted = Date()
        try await Task.sleep(for: .milliseconds(10))
        saveAMark()
        let second = try #require(keepAlive.unsentSince)
        #expect(second > uploadStarted)
        #expect(uploadStarted > first)

        keepAlive.exported(startedAt: uploadStarted)
        #expect(keepAlive.hasUnsentWork)
        #expect(keepAlive.unsentSince == second)

        keepAlive.exported(startedAt: Date())
        #expect(!keepAlive.hasUnsentWork)
    }

    // Sync and sharing bug hunt 2026-10-05: joining saves her membership row
    // in the private store, and Leave right after warned of unsent marks.
    @Test("On two stores, only the shared store's saves are unsent")
    func onlySharedStoreSavesCount() throws {
        let split = try splitContext()
        let keepAlive = UnsentChangesKeepAlive(viewContext: split.context)

        let membership = CDClassroomMembership(context: split.context)
        membership.id = UUID()
        #expect(split.context.safeSave())
        #expect(membership.objectID.persistentStore === split.privateStore)
        #expect(!keepAlive.hasUnsentWork)

        let record = CDAttendanceRecord(context: split.context)
        record.id = UUID()
        split.context.assign(record, to: split.sharedStore)
        #expect(split.context.safeSave())
        #expect(keepAlive.hasUnsentWork)
    }

    @Test("Leave's forget leaves nothing unsent and ends a wait")
    func forgetUnsent() async {
        let keepAlive = UnsentChangesKeepAlive(viewContext: context)
        saveAMark()
        Task { keepAlive.forgetUnsent() }
        await keepAlive.waitUntilSent(upTo: .seconds(60))
        #expect(!keepAlive.hasUnsentWork)
    }

    @Test("The app's own sending counts as unsent work")
    func appWork() {
        let busy = Flag(true)
        let keepAlive = UnsentChangesKeepAlive(viewContext: context, isBusy: { busy.value })
        #expect(keepAlive.hasUnsentWork)
        busy.value = false
        #expect(!keepAlive.hasUnsentWork)
    }

    @Test("Waiting returns when the export arrives, at once with nothing unsent, and at the limit otherwise")
    func waiting() async {
        let keepAlive = UnsentChangesKeepAlive(viewContext: context)
        await keepAlive.waitUntilSent(upTo: .seconds(60))

        saveAMark()
        Task { keepAlive.exported(startedAt: Date()) }
        await keepAlive.waitUntilSent(upTo: .seconds(60))
        #expect(!keepAlive.hasUnsentWork)

        saveAMark()
        let clock = ContinuousClock()
        let waited = await clock.measure { await keepAlive.waitUntilSent(upTo: .milliseconds(50)) }
        #expect(waited < .seconds(5))
        #expect(keepAlive.hasUnsentWork)
    }

    // Assistant battery and heat check 2026-10-10, finding 6: leaving with
    // unsent marks waited for the share attach with no limit, past 25 s up to
    // iOS's own cut-off. A sleep that returns at once stands in for the limit
    // passing; one cancelled when the work returns, for a limit not reached.

    @Test("Leaving waits for the app's own sending, then the export, as before")
    func leavingWaitsForSending() async {
        let sending = Gate()
        let keepAlive = UnsentChangesKeepAlive(viewContext: context, waitForWork: { await sending.wait() })
        saveAMark()
        let left = Flag(false)
        let leaving = Task {
            await keepAlive.sendBeforeSuspending(within: .seconds(60))
            left.value = true
        }
        await waitFor { sending.waiting == 1 }
        #expect(!left.value)

        sending.open()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!left.value)
        keepAlive.exported(startedAt: Date())
        await leaving.value
        #expect(left.value)
        #expect(!keepAlive.hasUnsentWork)
    }

    @Test("Sending that never finishes holds the app no longer than the limit", .timeLimit(.minutes(1)))
    func sendingPastTheLimit() async {
        let sending = Gate()
        let sent = Flag(false)
        let keepAlive = UnsentChangesKeepAlive(
            viewContext: context,
            waitForWork: {
                await sending.wait()
                sent.value = true
            },
            sleep: { _ in }
        )
        saveAMark()

        await keepAlive.sendBeforeSuspending()
        // Back with the sending still under way, and the mark still waiting
        // to go: only the wait ended.
        #expect(!sent.value)
        #expect(keepAlive.hasUnsentWork)

        // The sending carries on, and finishes when it can.
        sending.open()
        await waitFor { sent.value }
        #expect(sent.value)
    }

    @Test("A wait for work answers when the work returns, or false at the limit")
    func waitAtMost() async {
        let returned = await UnsentChangesKeepAlive.wait(atMost: .seconds(60)) {}
        #expect(returned)

        let sending = Gate()
        let late = await UnsentChangesKeepAlive.wait(
            atMost: .seconds(60), sleep: { _ in }, for: { await sending.wait() }
        )
        #expect(!late)
        sending.open()
    }

    @Test("Siri waits for its marks to go into the share, as before")
    func siriWaitsForTheAttach() async throws {
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(),
            attempt: { _, _, _ in CDAttendanceStore.ShareAttachResult(left: []) },
            zoneCheck: { _, _, _ in [] }
        )
        let mark = try savedMark()
        await SiriHost.didSave(created: [mark], in: stack, attacher: attacher)
        #expect(!attacher.isRunning)
        #expect(attacher.pending.isEmpty)
    }

    @Test("An attach that never finishes holds Siri's keep-alive no longer than its limit", .timeLimit(.minutes(1)))
    func siriAttachPastTheLimit() async throws {
        let cloudKit = Gate()
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(),
            attempt: { _, _, _ in
                await cloudKit.wait()
                return CDAttendanceStore.ShareAttachResult(left: [])
            },
            zoneCheck: { _, _, _ in [] }
        )
        let mark = try savedMark()
        await SiriHost.didSave(created: [mark], in: stack, attacher: attacher, sleep: { _ in })
        // The attach carries on, its mark still listed for the next try.
        #expect(attacher.isRunning)
        #expect(attacher.pending == [mark.uriRepresentation()])

        cloudKit.open()
        await attacher.waitUntilIdle()
        #expect(attacher.pending.isEmpty)
    }

    /// A mark saved, with its permanent ID.
    private func savedMark() throws -> NSManagedObjectID {
        let record = CDAttendanceRecord(context: context)
        record.id = UUID()
        try #require(context.safeSave())
        return record.objectID
    }

    /// Polls `condition` with a generous deadline: a passing run returns as
    /// soon as it holds.
    private func waitFor(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct Split {
        let context: NSManagedObjectContext
        let privateStore: NSPersistentStore
        let sharedStore: NSPersistentStore
    }

    /// Private and shared SQLite stores in a temporary folder, as on a phone.
    private func splitContext() throws -> Split {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var stores: [String: NSPersistentStore] = [:]
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            stores[configuration] = try coordinator.addPersistentStore(
                type: .sqlite, configuration: configuration, at: dir.appendingPathComponent("\(configuration).sqlite")
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return Split(
            context: context,
            privateStore: try #require(stores[CoreDataStack.privateConfiguration]),
            sharedStore: try #require(stores[CoreDataStack.sharedConfiguration])
        )
    }
}

@MainActor
private final class Flag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

/// Work that waits until a test opens it: the app's sending, or CloudKit.
@MainActor
private final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// How many are waiting now.
    var waiting: Int { waiters.count }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let resumed = waiters
        waiters = []
        resumed.forEach { $0.resume() }
    }
}
