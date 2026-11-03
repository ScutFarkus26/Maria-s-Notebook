import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-02, #25, #26, #27 and #28.
//
// #25: in the notebook any store's export ended the keep-alive's wait (and
// Siri's), so the private store's could let the iPad sleep while the
// classroom share's export, carrying the mark, was still to go.
// #26: one "no iCloud account" answer at launch lifted the first-download
// holds for the whole session, and nothing took the lift back.
// #27: events buffered until configure were dated when they were handled.
// #28: the last second of Sync History was lost at quit.

/// The defaults the sync status service writes, restored after each test.
@MainActor
private func withSavedSyncDefaults(_ body: () async throws -> Void) async rethrows {
    let keys = [
        UserDefaultsKeys.cloudKitLastSuccessfulSyncDate,
        UserDefaultsKeys.cloudKitLastSyncError,
        UserDefaultsKeys.cloudKitLastSyncErrorDetail,
        UserDefaultsKeys.cloudKitLastSyncErrorKind,
        UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate,
        UserDefaultsKeys.cloudKitErrorLog,
        UserDefaultsKeys.cloudKitLastErrorDescription
    ]
    let defaults = UserDefaults.standard
    let saved = keys.map { defaults.object(forKey: $0) }
    defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
    try await body()
}

@MainActor
private func makeService() -> CloudKitSyncStatusService {
    let service = CloudKitSyncStatusService(coreDataStack: nil)
    service.syncedStoreResolver = { identifier in
        SyncedStore(
            identifier: identifier, notebookIdentifier: "private-store", classroomShareIdentifier: "shared-store"
        )
    }
    return service
}

@Suite("Sync status: dates, the history at quit, the first download and the keep-alive", .serialized)
@MainActor
struct SyncStatusDatesAndKeepAliveTests {

    // MARK: - #27

    @Test("An import that finished before configure reads as synced when it finished")
    func bufferedSuccessKeepsItsDate() async throws {
        try await withSavedSyncDefaults {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            let ended = Date(timeIntervalSinceNow: -90)
            service.beginEarlyEventCapture(for: stack)
            service.receive(CloudKitEventValues(
                type: .import, isFinished: true, succeeded: true, error: nil,
                startDate: ended.addingTimeInterval(-5), storeIdentifier: "private-store", endDate: ended
            ))
            service.startHandlingCloudKitEvents(for: stack)

            #expect(service.lastSuccessfulSync == ended)
            #expect(service.lastOperationDate == ended)
        }
    }

    @Test("A failure that happened before configure is dated when it happened")
    func bufferedFailureKeepsItsDate() async throws {
        try await withSavedSyncDefaults {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            let ended = Date(timeIntervalSinceNow: -60)
            let refused = NSError(domain: CKErrorDomain, code: CKError.Code.serverRejectedRequest.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "Rejected"
            ])
            service.beginEarlyEventCapture(for: stack)
            service.receive(CloudKitEventValues(
                type: .export, isFinished: true, succeeded: false, error: refused,
                startDate: ended.addingTimeInterval(-2), storeIdentifier: "shared-store", endDate: ended
            ))
            service.startHandlingCloudKitEvents(for: stack)

            #expect(service.lastOperationDate == ended)
            let failure = try #require(service.storeHealth.mostSevereFailure)
            #expect(failure.store == .classroomShare)
            #expect(failure.date == ended)
        }
    }

    @Test("An event posted the moment the listener starts is heard", .timeLimit(.minutes(1)))
    func listensAsItStarts() async throws {
        try await withSavedSyncDefaults {
            // A `messages(of:for:)` sequence listened only once a task first
            // iterated it, so a setup event the stores posted meanwhile was
            // missed (2026-11-03 review). The listener now listens as it returns.
            let center = NotificationCenter()
            let service = makeService()
            defer {
                service.stopCloudKitEventStream()
                service.retryLogic.resetRetryCount()
            }
            let ended = Date(timeIntervalSinceNow: -5)
            service.startCloudKitEventStream(on: center) { note in
                guard note.object as? String == "early" else { return nil }
                return CloudKitEventValues(
                    type: .import, isFinished: true, succeeded: true, error: nil,
                    startDate: ended.addingTimeInterval(-1), storeIdentifier: "private-store", endDate: ended
                )
            }
            center.post(name: NSPersistentCloudKitContainer.eventChangedNotification, object: "early")
            let deadline = Date(timeIntervalSinceNow: 2)
            while service.bufferedEvents.isEmpty, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(service.bufferedEvents.count == 1)
            #expect(service.bufferedEvents.first?.endDate == ended)

            // Stopped, it hears nothing more.
            service.stopCloudKitEventStream()
            center.post(name: NSPersistentCloudKitContainer.eventChangedNotification, object: "early")
            try await Task.sleep(for: .milliseconds(50))
            #expect(service.bufferedEvents.count == 1)
        }
    }

    // MARK: - #28

    @Test("Going to the background writes the history row logged just before it")
    func backgroundFlushWritesTheLastRow() throws {
        let suiteName = "SyncStatusDatesAndKeepAliveTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "SyncHistory.events.flushTest"
        // A write that would come only after the test is over.
        let logger = SyncEventLogger(defaults: defaults, storageKey: key, coalesceWindow: 30, saveDelay: .seconds(600))
        logger.log("cloudkit", status: "error", message: "Sync stopped")
        #expect(defaults.data(forKey: key) == nil)

        makeService().flushForBackgroundOrQuit(eventLogger: logger)

        #expect(defaults.data(forKey: key) != nil)
        let reread = SyncEventLogger(defaults: defaults, storageKey: key, coalesceWindow: 30, saveDelay: .seconds(600))
        #expect(reread.events.map(\.message) == ["Sync stopped"])
    }

    @Test("With nothing waiting, the flush writes nothing")
    func backgroundFlushWithNothingWaitingWritesNothing() throws {
        let suiteName = "SyncStatusDatesAndKeepAliveTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "SyncHistory.events.flushTest"
        let logger = SyncEventLogger(defaults: defaults, storageKey: key, coalesceWindow: 30, saveDelay: .seconds(600))
        logger.flushPendingSave()
        #expect(defaults.data(forKey: key) == nil)
    }

    // MARK: - #26

    /// The account answers, and what the account step did with them.
    @MainActor
    private final class AccountScript {
        var statuses: [CKAccountStatus]
        var lifts: [Bool] = []
        var rechecks = 0
        var accountChanges = 0

        init(_ statuses: [CKAccountStatus]) { self.statuses = statuses }

        /// Answers in turn, then the last one for good.
        func next() -> CKAccountStatus {
            statuses.count > 1 ? statuses.removeFirst() : statuses[0]
        }
    }

    private func follow(_ script: AccountScript, defaults: UserDefaults) async throws {
        let context = try CoreDataTestHelpers.makeContext()
        await CloudKitSyncStatusService.followAccountForFirstDownload(
            context: context,
            accountStatus: { script.next() },
            defaults: defaults,
            setLifted: { script.lifts.append($0) },
            waitBeforeRecheck: { script.rechecks += 1 },
            waitForAccountChange: { script.accountChanges += 1 }
        )
    }

    private func armedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "SyncStatusDatesAndKeepAliveTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        FirstDownloadGate.arm(defaults: defaults)
        return (defaults, suiteName)
    }

    @Test("A moment's \u{201C}no account\u{201D} at launch lifts nothing")
    func oneNoAccountAnswerLiftsNothing() async throws {
        let (defaults, suiteName) = try armedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let script = AccountScript([.noAccount, .available])

        try await follow(script, defaults: defaults)

        #expect(script.rechecks == 1, "it asked again before lifting")
        #expect(script.lifts.isEmpty)
        #expect(FirstDownloadGate.isPending(defaults: defaults, liftedForSession: false))
    }

    @Test("Asked twice with no account, the holds lift; an account signing in takes the lift back")
    func liftIsTakenBackWhenAnAccountSignsIn() async throws {
        let (defaults, suiteName) = try armedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let script = AccountScript([.noAccount, .noAccount, .couldNotDetermine, .available])

        try await follow(script, defaults: defaults)

        #expect(script.lifts == [true, false])
        #expect(script.accountChanges == 2, "an unsure answer isn't an account")
        #expect(FirstDownloadGate.isArmed(defaults: defaults), "lifted, never opened")
    }

    @Test("An account that's there from the start skips the recheck")
    func accountThereSkipsEverything() async throws {
        let (defaults, suiteName) = try armedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let script = AccountScript([.available])

        try await follow(script, defaults: defaults)

        #expect(script.rechecks == 0)
        #expect(script.lifts.isEmpty)
    }

    // MARK: - #58 (the gate's two questions)

    @Test("Lifted for the session, the gate is no longer pending but still armed")
    func liftedGateIsStillArmed() throws {
        let (defaults, suiteName) = try armedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!FirstDownloadGate.isPending(defaults: defaults, liftedForSession: true))
        #expect(FirstDownloadGate.isArmed(defaults: defaults))
        FirstDownloadGate.open(defaults: defaults)
        #expect(!FirstDownloadGate.isArmed(defaults: defaults))
    }

    // MARK: - #25

    @Test("The private store's export doesn't cover the classroom share's save")
    func otherStoresExportLeavesTheWait() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let keepAlive = UnsentChangesKeepAlive(viewContext: stack.viewContext)
        let saved = Date(timeIntervalSinceNow: -10)
        keepAlive.saved(at: saved, stores: ["private-store", "shared-store"])

        keepAlive.exported(startedAt: saved.addingTimeInterval(1), storeIdentifier: "private-store")
        #expect(keepAlive.hasUnsentWork, "the share's export is still to go")
        #expect(keepAlive.unsentSinceByStore.keys.sorted() == ["shared-store"])

        // An export that began before the save doesn't hold it.
        keepAlive.exported(startedAt: saved.addingTimeInterval(-1), storeIdentifier: "shared-store")
        #expect(keepAlive.hasUnsentWork)

        keepAlive.exported(startedAt: saved.addingTimeInterval(2), storeIdentifier: "shared-store")
        #expect(!keepAlive.hasUnsentWork)
    }

    @Test("A save whose store isn't known waits for any store's export")
    func unknownStoreWaitsForAnyExport() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let keepAlive = UnsentChangesKeepAlive(viewContext: stack.viewContext)
        let saved = Date(timeIntervalSinceNow: -10)
        keepAlive.saved(at: saved)

        keepAlive.exported(startedAt: saved.addingTimeInterval(1), storeIdentifier: "private-store")
        #expect(!keepAlive.hasUnsentWork)
    }

    @Test("A save to both stores records each object's own store")
    func savedObjectsNameTheirStores() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let stores = try #require(context.persistentStoreCoordinator?.persistentStores)
        let privateStore = try #require(stores.first { $0.configurationName == CoreDataStack.privateConfiguration })
        let sharedStore = try #require(stores.first { $0.configurationName == CoreDataStack.sharedConfiguration })
        let student = CoreDataTestHelpers.seedStudent(in: context)
        context.assign(student, to: privateStore)
        let record = CoreDataTestHelpers.seedAttendance(in: context)
        context.assign(record, to: sharedStore)
        #expect(CoreDataTestHelpers.save(context))

        let named = UnsentChangesKeepAlive.storesToSend([student, record])
        #expect(named == Set([privateStore.identifier, sharedStore.identifier].compactMap { $0 }))
        #expect(named.count == 2)
    }

    @Test("Siri's wait ends on an export of a store the commit saved to, not another's")
    func siriWaitNeedsTheSavedStoresExport() {
        let ends = { (store: String?, saved: Set<String>?) in
            SiriExportWatch.ends(
                type: .export, ended: true, succeeded: true, startedSinceWatching: true,
                storeConfiguration: nil, storeIdentifier: store, savedStores: saved
            )
        }
        #expect(!ends("private-store", ["shared-store"]))
        #expect(ends("shared-store", ["shared-store"]))
        #expect(ends("private-store", ["private-store", "shared-store"]))
        // Before the save is known, or for an object with no known store, any store's export counts.
        #expect(ends("private-store", nil))
        #expect(ends("private-store", [UnsentChangesKeepAlive.anyStore]))
        // A failed or older export never ends it.
        #expect(!SiriExportWatch.ends(
            type: .export, ended: true, succeeded: false, startedSinceWatching: true,
            storeConfiguration: nil, storeIdentifier: "shared-store", savedStores: ["shared-store"]
        ))
    }
}
