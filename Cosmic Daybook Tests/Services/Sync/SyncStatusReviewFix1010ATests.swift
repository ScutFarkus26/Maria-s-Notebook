import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - The 2026-10-10 fixes' review round (sync status)
//
// A network setup failure of the guide's empty classroom-share store held his
// filing, which goes through the private store, perhaps until relaunch (#3).
// A stop set before any stack was known named no store (`.other`), and no
// later success cleared it (#4).

private func ckError(_ code: CKError.Code) -> NSError {
    NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: "CloudKit error"])
}

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

/// How many times the filing step was woken.
@MainActor
private final class Wakes {
    var count = 0
}

/// A service naming "private-store" the notebook and "shared-store" the
/// classroom share, that never waits to ask about the account again.
@MainActor
private func makeService(wakes: Wakes = Wakes()) -> CloudKitSyncStatusService {
    let service = CloudKitSyncStatusService()
    service.syncedStoreResolver = { identifier in
        SyncedStore(
            identifier: identifier, notebookIdentifier: "private-store", classroomShareIdentifier: "shared-store"
        )
    }
    service.accountStatus = { .available }
    service.filingHooks.waitBeforeAccountRecheck = {}
    service.filingHooks.wakeFiling = { wakes.count += 1 }
    return service
}

/// A finished event as it arrives from CloudKit's stream (`receive`).
@MainActor
private func arrive(
    _ service: CloudKitSyncStatusService,
    _ type: NSPersistentCloudKitContainer.EventType,
    store: String,
    error: NSError?,
    succeeded: Bool = false,
    startDate: Date = Date()
) {
    service.receive(CloudKitEventValues(
        type: type, isFinished: true, succeeded: succeeded, error: error,
        startDate: startDate, storeIdentifier: store
    ))
}

@Suite("Sync status: the fixes' review round (2026-10-10)", .serialized)
@MainActor
struct SyncStatusReviewFix1010ATests {

    @Test("A network setup failure holds only the notebook's store; no account holds either")
    func transientFailureHoldsOnlyTheNotebook() async {
        await withSavedDefaults {
            let service = makeService()
            arrive(service, .setup, store: "shared-store", error: ckError(.networkUnavailable))
            arrive(service, .setup, store: "shared-store", error: nil)
            #expect(service.shareFilingHold == nil, "his filing doesn't go through the classroom share's store")

            arrive(service, .setup, store: "private-store", error: ckError(.zoneBusy))
            #expect(service.shareFilingHold == .untilICloudReady)

            let other = makeService()
            arrive(other, .setup, store: "shared-store", error: ckError(.accountTemporarilyUnavailable))
            #expect(other.shareFilingHold == .untilICloudReady, "no account stops the whole container")
        }
    }

    @Test("A stop set before any stack was known names its store once the stack is, and its own sync clears it")
    func stopWithoutAStackIsFollowedAgain() async throws {
        try await withSavedDefaults {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let privateStore = try stack.container.persistentStoreCoordinator.addPersistentStore(
                type: .inMemory,
                configuration: CoreDataStack.privateConfiguration,
                at: URL(fileURLWithPath: "/dev/null/private-\(UUID().uuidString)")
            )
            let storeID = try #require(privateStore.identifier)
            let wakes = Wakes()
            // No resolver: stores are named from the stack, as in the app.
            let service = CloudKitSyncStatusService()
            service.filingHooks.wakeFiling = { wakes.count += 1 }
            let failedAt = Date()
            arrive(service, .setup, store: storeID, error: setupThrew, startDate: failedAt)
            #expect(service.stoppedStores == [.other], "no stack yet, so no store to name")

            service.beginEarlyEventCapture(for: stack)
            #expect(service.stoppedStores == [.notebook])
            let later = failedAt.addingTimeInterval(1)
            arrive(service, .export, store: storeID, error: nil, succeeded: true, startDate: later)
            #expect(!service.mirroringDelegateFailed, "the notebook's own sync clears it")
            #expect(wakes.count == 1)
        }
    }
}
