import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - What counts as synced (2026-10-05 sync and sharing hunt, #6 and #7)
//
// A remote change is posted for this device's own saves too, the automatic
// retry pretended to be Sync Now, the toolbar dot ignored per-store failures,
// setup events before `configure` went unseen, and the stopped flag never
// cleared. These pin the fixes with synthetic events.

private func ckError(_ code: CKError.Code, _ message: String = "CloudKit error") -> NSError {
    NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
}

private let noAccount = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
    NSLocalizedDescriptionKey: "Unable to initialize without an iCloud account."
])

private let setupThrew = NSError(domain: NSCocoaErrorDomain, code: 134_060, userInfo: [
    NSLocalizedDescriptionKey: "A Core Data error occurred."
])

/// Polls until `condition` holds or 10 s pass; the test's own expectations then decide.
@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// The defaults these suites' services write, restored after each test.
@MainActor
private func withSavedDefaults(_ body: () async throws -> Void) async rethrows {
    let keys = [
        UserDefaultsKeys.cloudKitLastSuccessfulSyncDate,
        UserDefaultsKeys.cloudKitLastSyncError,
        UserDefaultsKeys.cloudKitLastSyncErrorDetail,
        UserDefaultsKeys.cloudKitLastSyncErrorKind,
        UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate,
        UserDefaultsKeys.cloudKitErrorLog,
        UserDefaultsKeys.cloudKitLastErrorDescription,
        FirstDownloadGate.key
    ]
    let defaults = UserDefaults.standard
    let saved = keys.map { defaults.object(forKey: $0) }
    defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
    try await body()
}

@MainActor
private func makeService(stack: CoreDataStack? = nil) -> CloudKitSyncStatusService {
    let service = CloudKitSyncStatusService(coreDataStack: stack)
    service.syncedStoreResolver = { identifier in
        SyncedStore(
            identifier: identifier, notebookIdentifier: "private-store", classroomShareIdentifier: "shared-store"
        )
    }
    return service
}

@MainActor
private func finish(
    _ service: CloudKitSyncStatusService,
    _ type: NSPersistentCloudKitContainer.EventType,
    store: String,
    error: NSError? = nil
) {
    service.handleCloudKitEvent(
        type: type, isFinished: true, succeeded: error == nil, error: error,
        startDate: Date(), storeIdentifier: store
    )
}

@Suite("Sync status: only iCloud's own events say it synced", .serialized)
@MainActor
struct SyncStatusTruthTests {

    // MARK: #6a A remote change

    @Test("A remote change doesn't stamp success, clear the error, zero the count or end the save's wait")
    func remoteChangeStampsNothing() async {
        await withSavedDefaults {
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            let before = Date(timeIntervalSince1970: 1_000_000)
            service.lastSuccessfulSync = before
            service.recordSyncError("You're offline.", detail: nil, kind: .network, persist: false)
            service.pendingSyncCount = 2
            service.isSyncing = true
            let wait = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
            service.syncingTask = wait
            defer { wait.cancel() }

            service.handleRemoteChange()

            #expect(service.lastSuccessfulSync == before)
            #expect(service.lastSyncError == "You're offline.")
            #expect(service.pendingSyncCount == 2)
            #expect(service.isSyncing)
            #expect(service.syncingTask != nil)
            #expect(!wait.isCancelled)

            // A successful export is what clears them.
            finish(service, .export, store: "private-store")
            #expect(service.lastSuccessfulSync.map { $0 > before } == true)
            #expect(service.lastSyncError == nil)
            #expect(service.pendingSyncCount == 0)
            #expect(!service.isSyncing)
            #expect(wait.isCancelled)
        }
    }

    @Test("While the first download is pending a remote change keeps the overlay up, whatever the last sync date")
    func overlayFollowsFirstDownloadGate() async {
        await withSavedDefaults {
            let service = makeService()
            // Reset Local Cache keeps the old last-sync date; that used to hide the overlay.
            service.lastSuccessfulSync = Date()
            FirstDownloadGate.arm()
            #expect(service.isFirstDownload)
            service.noteCloudImportActivity()
            #expect(service.isImportingFromCloud)
            service.handleRemoteChange()
            #expect(service.isImportingFromCloud)
            service.cloudImportDebounceTask?.cancel()

            FirstDownloadGate.open()
            let settled = makeService()
            settled.noteCloudImportActivity()
            #expect(!settled.isImportingFromCloud)
        }
    }

    // MARK: #6b Retries

    @Test("A retry logs no tap, stamps nothing and keeps the error")
    func retryIsNotSyncNow() async throws {
        try await withSavedDefaults {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let service = makeService(stack: stack)
            let before = Date(timeIntervalSince1970: 1_000_000)
            service.lastSuccessfulSync = before
            service.recordSyncError("iCloud sync didn't finish.", detail: nil, kind: .other, persist: false)
            let taps = SyncEventLogger.shared.events.filter { $0.message == "You tapped Sync Now" }.count

            #expect(await service.retrySync())

            #expect(SyncEventLogger.shared.events.filter { $0.message == "You tapped Sync Now" }.count == taps)
            #expect(service.lastSuccessfulSync == before)
            #expect(service.lastSyncError == "iCloud sync didn't finish.")
        }
    }

    @Test("Sync Now saves, but neither stamps a sync nor clears the error")
    func syncNowClaimsNothing() async throws {
        try await withSavedDefaults {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let service = makeService(stack: stack)
            let before = Date(timeIntervalSince1970: 1_000_000)
            service.lastSuccessfulSync = before
            service.recordSyncError("iCloud sync didn't finish.", detail: nil, kind: .other, persist: false)

            #expect(await service.syncNow())

            #expect(service.lastSuccessfulSync == before)
            #expect(service.lastSyncError == "iCloud sync didn't finish.")
        }
    }

    @Test("A finished retry clears its task, so it stops saying \u{201C}Trying again soon\u{201D}")
    func finishedRetryClearsTask() async throws {
        let logic = SyncRetryLogic(baseRetryDelay: 0.01)
        var runs = 0
        logic.scheduleRetry(canRetry: { true }, syncAction: { runs += 1; return true }, onMaxRetriesReached: {})
        #expect(logic.hasPendingRetry)
        try await waitUntil { runs == 1 && !logic.hasPendingRetry }
        #expect(!logic.hasPendingRetry)
        #expect(logic.retryAttempt == 1)
    }

    @Test("Waiting offline doesn't use up attempts")
    func offlineWaitKeepsAttempts() async throws {
        let logic = SyncRetryLogic(baseRetryDelay: 0.01)
        var ran = false
        logic.scheduleRetry(canRetry: { false }, syncAction: { ran = true; return true }, onMaxRetriesReached: {})
        try await waitUntil { !logic.hasPendingRetry }
        #expect(logic.retryAttempt == 0)
        #expect(!ran)
    }

    // MARK: #7b The stopped flag

    @Test("A failed setup sets the flag; only that store's later import or export clears it")
    func flagClearsOnSameStoreSuccess() async {
        await withSavedDefaults {
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            finish(service, .setup, store: "shared-store", error: setupThrew)
            #expect(service.mirroringDelegateFailed)

            finish(service, .export, store: "private-store")
            #expect(service.mirroringDelegateFailed, "the notebook's success says nothing about the share")
            finish(service, .setup, store: "shared-store")
            #expect(service.mirroringDelegateFailed, "a setup success alone isn't recovery")

            // (An export: an import would also start a dedup pass in the test host.)
            finish(service, .export, store: "shared-store")
            #expect(!service.mirroringDelegateFailed)
            #expect(service.storeHealth.mostSevereFailure == nil)
        }
    }

    @Test("No account or no network at setup doesn't mark sync stopped")
    func accountAndNetworkSetupFailuresDontStop() async {
        await withSavedDefaults {
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            finish(service, .setup, store: "private-store", error: noAccount)
            finish(service, .setup, store: "shared-store", error: ckError(.networkUnavailable))
            #expect(!service.mirroringDelegateFailed)
            #expect(service.storeHealth.outstandingFailures.allSatisfy { $0.severity == .retrying })
        }
    }

    @Test("A flag set while attaching (no store named) clears on the classroom share's next export")
    func attachFlagClearsOnShareExport() async {
        await withSavedDefaults {
            let service = makeService()
            service.mirroringDelegateFailed = true
            finish(service, .export, store: "private-store")
            #expect(service.mirroringDelegateFailed)
            finish(service, .export, store: "shared-store")
            #expect(!service.mirroringDelegateFailed)
        }
    }

    // MARK: #7a Events before configure

    @Test("A setup failure before configure is handled once configure runs")
    func earlySetupFailureIsSeen() async throws {
        try await withSavedDefaults {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            service.beginEarlyEventCapture(for: stack)
            service.receive(CloudKitEventValues(
                type: .setup, isFinished: true, succeeded: false, error: setupThrew,
                startDate: Date(), storeIdentifier: "shared-store"
            ))
            #expect(!service.mirroringDelegateFailed)
            #expect(service.storeHealth.mostSevereFailure == nil)

            service.startHandlingCloudKitEvents(for: stack)
            #expect(service.mirroringDelegateFailed)
            let failure = try #require(service.storeHealth.mostSevereFailure)
            #expect(failure.store == .classroomShare)
            #expect(failure.eventType == .setup)
            #expect(failure.severity == .stopped)
            #expect(service.bufferedEvents.isEmpty)
        }
    }
}

@Suite("Sync status: the dot, the account, early events and error codes", .serialized)
@MainActor
struct SyncStatusSignalsTests {

    @Test("Another stack's early events are dropped")
    func otherStacksEventsDropped() async throws {
        try await withSavedDefaults {
            let early = try CoreDataTestHelpers.makeInMemoryStack()
            let configured = try CoreDataTestHelpers.makeInMemoryStack()
            let service = makeService()
            service.beginEarlyEventCapture(for: early)
            service.receive(CloudKitEventValues(
                type: .setup, isFinished: true, succeeded: false, error: setupThrew,
                startDate: Date(), storeIdentifier: "private-store"
            ))
            service.startHandlingCloudKitEvents(for: configured)
            #expect(!service.mirroringDelegateFailed)
            #expect(service.storeHealth.mostSevereFailure == nil)
        }
    }

    // MARK: #6c The toolbar dot

    @Test("The dot shows a stopped store even when the shown error is clear")
    func dotFollowsStoreHealth() async {
        await withSavedDefaults {
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            finish(service, .export, store: "shared-store", error: ckError(.serverRejectedRequest, "Rejected"))
            finish(service, .export, store: "private-store")
            #expect(service.lastSyncError == nil)
            #expect(SyncDotVisibility.state(for: service) == .stopped)
            #expect(SyncDotVisibility.isShown(for: service))

            finish(service, .export, store: "shared-store")
            finish(service, .export, store: "private-store", error: ckError(.networkFailure))
            service.clearSyncErrorInMemory()
            #expect(SyncDotVisibility.state(for: service) == .problem)
        }
    }

    @Test("The dot's states: offline, signed out, stopped beats syncing")
    func dotStates() {
        func state(network: Bool = true, signedOut: Bool = false, stopped: Bool = false,
                   syncing: Bool = false, pending: Int = 0, error: Bool = false) -> SyncDotState {
            SyncDotVisibility.state(
                isNetworkAvailable: network, isSignedOut: signedOut, isStopped: stopped,
                isSyncing: syncing, pendingLocalChanges: pending, hasError: error
            )
        }
        #expect(state(network: false, stopped: true) == .offline)
        #expect(state(signedOut: true) == .signedOut)
        #expect(state(stopped: true, syncing: true) == .stopped)
        #expect(state(pending: 3) == .waiting(3))
        #expect(state() == .synced)
        #expect(SyncDotState.stopped.text.contains("CKError") == false)
    }

    // MARK: Signed out and another account

    @Test("Signed out reads as offline; a sign-in is no account switch, another record name is")
    func accountChanges() {
        let check = CloudKitHealthCheck()
        let first = check.recordAccountStatus(available: true, userRecordName: "_alice")
        #expect(first == CloudKitHealthCheck.AccountChange(isAvailable: true, isDifferentAccount: false))
        #expect(check.recordAccountStatus(available: true, userRecordName: "_alice") == nil)

        #expect(check.recordAccountStatus(available: false, userRecordName: nil)
            == CloudKitHealthCheck.AccountChange(isAvailable: false, isDifferentAccount: false))
        #expect(check.isSignedOut)
        check.updateSyncHealth(
            isSyncing: false, lastSuccessfulSync: Date(), lastSyncError: nil,
            isNetworkAvailable: true, isEnabled: true, isActive: true
        )
        #expect(check.syncHealth == .offline)

        #expect(check.recordAccountStatus(available: true, userRecordName: "_bob")
            == CloudKitHealthCheck.AccountChange(isAvailable: true, isDifferentAccount: true))
        #expect(!check.isSignedOut)
    }

    @Test("Another account starts this service over: dates, flag, store health, error")
    func newAccountResets() async {
        await withSavedDefaults {
            let service = makeService()
            finish(service, .setup, store: "shared-store", error: setupThrew)
            finish(service, .export, store: "private-store")
            #expect(service.mirroringDelegateFailed)
            #expect(service.lastSuccessfulSync != nil)

            service.resetForNewAccount()

            #expect(!service.mirroringDelegateFailed)
            #expect(service.stoppedStores.isEmpty)
            #expect(service.lastSuccessfulSync == nil)
            #expect(UserDefaults.standard.object(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate) == nil)
            #expect(service.storeHealth.knownStores.isEmpty)
            #expect(service.lastSyncError == nil)
            let defaults = UserDefaults.standard
            #expect(defaults.object(forKey: UserDefaultsKeys.cloudKitLastSuccessfulImportStartByStore) == nil)
            #expect(defaults.object(forKey: UserDefaultsKeys.cloudKitLastSuccessfulExportStartByStore) == nil)
        }
    }

    // MARK: Error codes

    @Test("A lost response and a busy zone are temporary; a missing zone or full share isn't a refusal")
    func codesReadRight() {
        #expect(CloudKitStoreHealth.detail(of: ckError(.serverResponseLost)).cause == .transient)
        #expect(CloudKitStoreHealth.detail(of: ckError(.zoneBusy)).cause == .transient)
        for code: CKError.Code in [.zoneNotFound, .tooManyParticipants] {
            let detail = CloudKitStoreHealth.detail(of: ckError(code))
            #expect(!detail.stops)
            #expect(!detail.cause.isServerRefusal)
        }
        #expect(CloudKitConfigurationService.categorizeError(ckError(.limitExceeded)) == .unknown)
        #expect(CloudKitConfigurationService.categorizeError(ckError(.zoneNotFound)) == .unknown)
        #expect(CloudKitConfigurationService.categorizeError(ckError(.tooManyParticipants)) == .unknown)
        #expect(CloudKitConfigurationService.categorizeError(ckError(.serverResponseLost)) == .network)
    }
}
