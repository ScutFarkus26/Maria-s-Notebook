import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - The store behind a stop, and the account holds (bug hunt 2026-10-09, #2)
//
// An attach to the classroom share that found the mirroring delegate dead used
// to name no store, and the flag assumed the classroom share's: the guide's
// empty shared store syncing cleared it, and filing tried the dead private
// store again. Only a success that began after a store stopped clears it now.
// A setup that failed for want of an iCloud account holds filing into the
// share: with none signed in, until the app is reopened (Danny's call); with
// one signed in but not ready yet, until that store has set up and synced.

private func ckError(_ code: CKError.Code, _ message: String = "CloudKit error") -> NSError {
    NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
}

private let noAccount = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
    NSLocalizedDescriptionKey: "Unable to initialize without an iCloud account."
])

private let setupThrew = NSError(domain: NSCocoaErrorDomain, code: 134_060, userInfo: [
    NSLocalizedDescriptionKey: "A Core Data error occurred."
])

/// The defaults these tests' services write, restored after each test.
@MainActor
private func withSavedDefaults(_ body: () async throws -> Void) async rethrows {
    let keys = [
        UserDefaultsKeys.cloudKitLastSuccessfulSyncDate,
        UserDefaultsKeys.cloudKitLastSyncError,
        UserDefaultsKeys.cloudKitLastSyncErrorDetail,
        UserDefaultsKeys.cloudKitLastSyncErrorKind,
        UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate,
        UserDefaultsKeys.cloudKitLastSuccessfulImportStartByStore,
        UserDefaultsKeys.cloudKitLastSuccessfulExportStartByStore,
        UserDefaultsKeys.cloudKitErrorLog,
        UserDefaultsKeys.cloudKitLastErrorDescription,
        FirstDownloadGate.key
    ]
    let defaults = UserDefaults.standard
    let saved = keys.map { defaults.object(forKey: $0) }
    defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
    try await body()
}

/// Polls until `condition` holds or 5 s pass; the test's own expectations then decide.
@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// A service whose account status, if asked, is `status`; `asks` counts the asking.
@MainActor
private func makeService(
    accountStatus status: CKAccountStatus = .available, asks: AccountAsks = AccountAsks()
) -> CloudKitSyncStatusService {
    let service = CloudKitSyncStatusService()
    service.syncedStoreResolver = { identifier in
        SyncedStore(
            identifier: identifier, notebookIdentifier: "private-store", classroomShareIdentifier: "shared-store"
        )
    }
    service.accountStatus = {
        asks.count += 1
        return status
    }
    return service
}

/// An event handed straight to the handlers.
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

/// An event as it arrives from CloudKit's stream (`receive`), where the
/// account holds are followed. A service not yet configured keeps it for later.
@MainActor
private func arrive(
    _ service: CloudKitSyncStatusService,
    _ type: NSPersistentCloudKitContainer.EventType,
    store: String,
    error: NSError? = nil,
    startDate: Date = Date()
) {
    service.receive(CloudKitEventValues(
        type: type, isFinished: true, succeeded: error == nil, error: error,
        startDate: startDate, storeIdentifier: store
    ))
}

/// How many times a test service asked for the account status.
@MainActor
private final class AccountAsks {
    var count = 0
}

extension SyncStatusTruthTests {

    // MARK: The store behind a failed attach

    @Test("A failed attach names the store it ran against: the share's success leaves it stopped, its own clears it")
    func attachFlagNamesItsStore() async {
        await withSavedDefaults {
            let service = makeService()
            // The guide's attaches run against the private store (the notebook).
            service.markMirroringStopped(byAttachToStoreWithIdentifier: "private-store")
            #expect(service.mirroringDelegateFailed)
            #expect(service.stoppedStores == [.notebook])

            // His empty shared store syncing says nothing about the notebook's delegate.
            finish(service, .export, store: "shared-store")
            #expect(service.mirroringDelegateFailed, "the classroom share's success must not clear the notebook")
            finish(service, .setup, store: "private-store")
            #expect(service.mirroringDelegateFailed, "a setup success alone isn't recovery")

            finish(service, .export, store: "private-store")
            #expect(!service.mirroringDelegateFailed)
            #expect(service.stoppedStores.isEmpty)
        }
    }

    @Test("Two stopped stores: the flag holds until each has synced again")
    func flagHoldsUntilEveryStoreRecovers() async {
        await withSavedDefaults {
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            finish(service, .setup, store: "shared-store", error: setupThrew)
            service.markMirroringStopped(byAttachToStoreWithIdentifier: "private-store")
            #expect(service.stoppedStores == [.notebook, .classroomShare])

            finish(service, .export, store: "shared-store")
            #expect(service.mirroringDelegateFailed)
            #expect(service.stoppedStores == [.notebook])
            finish(service, .export, store: "private-store")
            #expect(!service.mirroringDelegateFailed)
        }
    }

    @Test("An attach before configure stays stopped when the launch's earlier success is handed over")
    func earlierSuccessDoesNotClearALaterStop() async throws {
        try await withSavedDefaults {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let service = makeService()
            service.beginEarlyEventCapture(for: stack)
            // The launch's export finished; then Siri, in the background, found the delegate dead.
            arrive(service, .export, store: "private-store", startDate: Date().addingTimeInterval(-30))
            service.markMirroringStopped(byAttachToStoreWithIdentifier: "private-store")

            service.startHandlingCloudKitEvents(for: stack)
            #expect(service.bufferedEvents.isEmpty, "the export was handed over")
            #expect(service.mirroringDelegateFailed, "a success from before the stop proves nothing")
            #expect(service.stoppedStores == [.notebook])

            finish(service, .export, store: "private-store")
            #expect(!service.mirroringDelegateFailed)
        }
    }

    // MARK: The account at setup

    @Test("Signed in but not ready: filing waits, and lifts once that store has set up and synced again")
    func notReadyAccountHoldsUntilSetUpAndSynced() async throws {
        try await withSavedDefaults {
            let asks = AccountAsks()
            let service = makeService(accountStatus: .noAccount, asks: asks)
            // The Mac app opening at login, before configure.
            #expect(!service.handlesCloudKitEvents)
            arrive(service, .setup, store: "private-store", error: ckError(.accountTemporarilyUnavailable))
            #expect(service.shareFilingHold == .untilICloudReady)

            arrive(service, .export, store: "private-store")
            #expect(service.shareFilingHold == .untilICloudReady, "no setup has succeeded yet")
            arrive(service, .setup, store: "private-store")
            #expect(service.shareFilingHold == .untilICloudReady, "set up, but nothing synced since")
            arrive(service, .export, store: "shared-store")
            #expect(service.shareFilingHold == .untilICloudReady, "another store's sync says nothing")

            arrive(service, .import, store: "private-store")
            #expect(service.shareFilingHold == nil)
            #expect(service.accountNotReadyStores.isEmpty)
            // The error said "not ready": CloudKit wasn't asked, so no pause until reopening.
            try await Task.sleep(for: .milliseconds(50))
            #expect(asks.count == 0)
            #expect(!service.shareFilingPausedUntilReopen)
        }
    }

    @Test("Core Data's no-account error while the account is only not ready yet holds filing just as long")
    func noAccountErrorWithAccountNotReady() async throws {
        try await withSavedDefaults {
            let asks = AccountAsks()
            let service = makeService(accountStatus: .temporarilyUnavailable, asks: asks)
            arrive(service, .setup, store: "private-store", error: noAccount)
            #expect(service.shareFilingHold == .untilICloudReady)
            try await waitUntil { asks.count == 1 }
            try await Task.sleep(for: .milliseconds(50))
            #expect(asks.count == 1)
            #expect(!service.shareFilingPausedUntilReopen)

            arrive(service, .setup, store: "private-store")
            arrive(service, .export, store: "private-store")
            #expect(service.shareFilingHold == nil)
        }
    }

    @Test("With no iCloud account at all, filing pauses until the app is reopened, whatever follows")
    func noAccountPausesUntilReopen() async throws {
        try await withSavedDefaults {
            let service = makeService(accountStatus: .noAccount)
            defer { service.retryLogic.resetRetryCount() }
            arrive(service, .setup, store: "private-store", error: noAccount)
            try await waitUntil { service.shareFilingPausedUntilReopen }
            #expect(service.shareFilingHold == .untilReopen)
            // Not a dead delegate: the dot doesn't say sync stopped.
            #expect(!service.mirroringDelegateFailed)

            // Another account signing in, and the stores setting up and syncing, leave it paused.
            service.resetForNewAccount()
            arrive(service, .setup, store: "private-store")
            arrive(service, .export, store: "private-store")
            arrive(service, .export, store: "shared-store")
            #expect(service.shareFilingPausedUntilReopen, "resetForNewAccount and later successes must not clear it")
            #expect(service.shareFilingHold == .untilReopen)
        }
    }

    @Test("Only a setup that wanted an account holds filing: not the network, not another failure, not an import")
    func onlyAccountSetupFailuresHold() async {
        await withSavedDefaults {
            #expect(CloudKitStoreHealth.isAccountUnavailable(noAccount))
            #expect(CloudKitStoreHealth.isAccountUnavailable(ckError(.notAuthenticated)))
            #expect(CloudKitStoreHealth.isAccountUnavailable(ckError(.accountTemporarilyUnavailable)))
            #expect(!CloudKitStoreHealth.isAccountUnavailable(ckError(.networkUnavailable)))
            #expect(!CloudKitStoreHealth.isAccountUnavailable(setupThrew))
            #expect(CloudKitStoreHealth.isAccountNotReadyYet(ckError(.accountTemporarilyUnavailable)))
            #expect(!CloudKitStoreHealth.isAccountNotReadyYet(noAccount))

            let service = makeService()
            arrive(service, .setup, store: "private-store", error: ckError(.networkUnavailable))
            arrive(service, .setup, store: "shared-store", error: setupThrew)
            arrive(service, .import, store: "private-store", error: noAccount)
            #expect(service.shareFilingHold == nil)
            #expect(!service.shareFilingPausedUntilReopen)
        }
    }

    @Test("What the sync status says while filing is held is plain")
    func holdMessagesArePlain() {
        #expect(CloudKitSyncStatusService.ShareFilingHold.untilReopen.message
            == "iCloud wasn't ready when the notebook opened. Quit and reopen it to finish sharing.")
        #expect(CloudKitSyncStatusService.ShareFilingHold.untilICloudReady.message
            == "iCloud isn't ready yet. Sharing will pick up once it is.")
        for hold in [CloudKitSyncStatusService.ShareFilingHold.untilReopen, .untilICloudReady] {
            for jargon in ["CloudKit", "account", "setup", "134400", "store"] {
                #expect(!hold.message.localizedCaseInsensitiveContains(jargon))
            }
        }
    }
}
