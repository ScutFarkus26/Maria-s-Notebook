import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - Per-store sync health
//
// On 2026-09-30 the classroom share's export was refused by the Production
// schema and its mirroring delegate never initialized again, while the
// notebook store kept importing. Each notebook success cleared the one global
// error, so Settings and `sync_status` said "healthy". These replay that with
// synthetic events: a failure belongs to one store and one event kind, and
// only a later success of the same kind on the same store clears it.

private let schemaMessage = "Cannot create new type CD_AttendanceEmailSettings in production schema"
private let classroomZone = CKRecordZone.ID(
    zoneName: "com.apple.coredata.cloudkit.share.DB5879EF", ownerName: CKCurrentUserDefaultName
)

private func ckError(_ code: CKError.Code, _ message: String? = nil, userInfo: [String: Any] = [:]) -> NSError {
    var info = userInfo
    if let message { info[NSLocalizedDescriptionKey] = message }
    return NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: info)
}

/// The export error from the incident: a partial failure whose per-record
/// errors are the schema refusal and the batch siblings it took down.
private func productionSchemaRejection() -> NSError {
    ckError(.partialFailure, "Failed to modify some records", userInfo: [
        CKPartialErrorsByItemIDKey: [
            CKRecord.ID(recordName: "a", zoneID: classroomZone): ckError(.batchRequestFailed, "Atomic failure"),
            CKRecord.ID(recordName: "b", zoneID: classroomZone): ckError(
                .invalidArguments, "Invalid Arguments", userInfo: ["ServerErrorDescription": schemaMessage]
            ),
            CKRecord.ID(recordName: "c", zoneID: classroomZone): ckError(.batchRequestFailed, "Atomic failure")
        ]
    ])
}

@Suite("Sync status: per-store health")
@MainActor
struct CloudKitStoreHealthTests {

    // MARK: Reading the error

    @Test("A schema refusal inside a partial failure is read out, verbatim, and stops sync")
    func readsServerMessageFromPartialFailure() {
        let detail = CloudKitStoreHealth.detail(of: productionSchemaRejection())
        #expect(detail.message == schemaMessage)
        #expect(detail.code == "CKError 12")
        #expect(detail.stops)
    }

    @Test("serverRejectedRequest wrapped by Core Data still stops sync")
    func wrappedServerRejection() {
        let rejected = ckError(.serverRejectedRequest, "Server rejected the request")
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [NSUnderlyingErrorKey: rejected])
        let detail = CloudKitStoreHealth.detail(of: wrapped)
        #expect(detail.code == "CKError 15")
        #expect(detail.message == "Server rejected the request")
        #expect(detail.stops)
    }

    @Test("Network trouble and a busy zone are retried, not stopped")
    func transientErrorsRetry() {
        #expect(!CloudKitStoreHealth.detail(of: ckError(.networkFailure, "The network connection was lost")).stops)
        let busy = ckError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "a"): ckError(.zoneBusy, "Zone busy")]
        ])
        let detail = CloudKitStoreHealth.detail(of: busy)
        #expect(!detail.stops)
        #expect(detail.message == "Zone busy")
    }

    @Test("The mirroring delegate's 'never successfully initialized' stops sync")
    func neverInitializedStops() {
        let aborted = NSError(domain: NSCocoaErrorDomain, code: 134_406, userInfo: [
            NSLocalizedDescriptionKey: "The request was aborted because the mirroring delegate "
                + "never successfully initialized."
        ])
        #expect(CloudKitStoreHealth.detail(of: aborted).stops)
    }

    // MARK: Tracking

    @Test("A failed export marks only its store, names it plainly, and quotes the server in details")
    func failureNamesStoreAndQuotesServer() throws {
        var health = CloudKitStoreHealth()
        health.recordFinishedEvent(store: .notebook, type: .import, succeeded: true, error: nil)
        health.recordFinishedEvent(
            store: .classroomShare, type: .export, succeeded: false, error: productionSchemaRejection()
        )

        let failure = try #require(health.mostSevereFailure)
        #expect(failure.store == .classroomShare)
        #expect(failure.eventType == .export)
        #expect(failure.severity == .stopped)
        #expect(failure.message.hasPrefix("The classroom share can't send changes to iCloud right now."))
        #expect(!failure.message.contains(schemaMessage))
        #expect(!failure.message.contains("CKError"))
        #expect(failure.details.hasPrefix("Classroom share export failed"))
        #expect(failure.details.contains("\u{201C}\(schemaMessage)\u{201D}"))
        #expect(failure.details.contains("CKError 12"))
        #expect(health.failures(for: .notebook).isEmpty)
    }

    @Test("The other store's successes, and other kinds on the same store, do not clear it")
    func onlySameStoreSameKindClears() {
        var health = CloudKitStoreHealth()
        health.recordFinishedEvent(
            store: .classroomShare, type: .export, succeeded: false, error: productionSchemaRejection()
        )
        health.recordFinishedEvent(store: .notebook, type: .export, succeeded: true, error: nil)
        health.recordFinishedEvent(store: .notebook, type: .import, succeeded: true, error: nil)
        health.recordFinishedEvent(store: .classroomShare, type: .import, succeeded: true, error: nil)
        health.recordFinishedEvent(store: .classroomShare, type: .setup, succeeded: true, error: nil)
        #expect(health.mostSevereFailure?.store == .classroomShare)

        health.recordFinishedEvent(store: .classroomShare, type: .export, succeeded: true, error: nil)
        #expect(health.mostSevereFailure == nil)
        #expect(health.outstandingFailures.isEmpty)
    }

    @Test("A repeated failure keeps the date it started, and shows the newest error")
    func repeatedFailureKeepsFirstDate() throws {
        var health = CloudKitStoreHealth()
        let first = Date(timeIntervalSince1970: 1_000_000)
        health.recordFinishedEvent(
            store: .classroomShare, type: .export, succeeded: false,
            error: ckError(.networkFailure, "Lost"), at: first
        )
        health.recordFinishedEvent(
            store: .classroomShare, type: .export, succeeded: false,
            error: productionSchemaRejection(), at: first.addingTimeInterval(600)
        )
        let failure = try #require(health.mostSevereFailure)
        #expect(failure.date == first)
        #expect(failure.serverMessage == schemaMessage)
        #expect(failure.severity == .stopped)
    }

    @Test("A failed setup stops the store even with no error attached")
    func setupFailureStops() throws {
        var health = CloudKitStoreHealth()
        health.recordFinishedEvent(store: .notebook, type: .setup, succeeded: false, error: nil)
        let failure = try #require(health.mostSevereFailure)
        #expect(failure.severity == .stopped)
        #expect(failure.message.hasPrefix("Your notebook can't sync with iCloud right now."))
        #expect(failure.details.hasPrefix("Notebook setup failed"))
    }

    @Test("A stopped store outranks a retrying one; notebook lists first")
    func ordering() {
        var health = CloudKitStoreHealth()
        health.recordFinishedEvent(
            store: .notebook, type: .export, succeeded: false, error: ckError(.networkFailure, "Lost")
        )
        health.recordFinishedEvent(
            store: .classroomShare, type: .export, succeeded: false, error: productionSchemaRejection()
        )
        #expect(health.outstandingFailures.map(\.store) == [.classroomShare, .notebook])
        #expect(health.outstandingFailures.map(\.severity) == [.stopped, .retrying])
        #expect(health.knownStores == [.notebook, .classroomShare])
    }

    @Test("Store identifiers resolve to the notebook, the classroom share, or neither")
    func resolvesStores() {
        func store(_ id: String?) -> SyncedStore {
            SyncedStore(identifier: id, notebookIdentifier: "P", classroomShareIdentifier: "S")
        }
        #expect(store("P") == .notebook)
        #expect(store("S") == .classroomShare)
        #expect(store("X") == .other)
        #expect(store(nil) == .other)
    }

    // MARK: Overall health

    private func health(
        storeFailure: StoreSyncFailure?,
        isSyncing: Bool = false,
        lastSyncError: String? = nil,
        lastSuccessfulSync: Date? = Date()
    ) -> CloudKitHealthCheck.SyncHealth {
        let check = CloudKitHealthCheck()
        check.updateSyncHealth(
            isSyncing: isSyncing, lastSuccessfulSync: lastSuccessfulSync, lastSyncError: lastSyncError,
            isNetworkAvailable: true, isEnabled: true, isActive: true, storeFailure: storeFailure
        )
        return check.syncHealth
    }

    @Test("A stopped store is an error even right after the other store synced, or while it syncs")
    func stoppedStoreIsError() throws {
        var tracker = CloudKitStoreHealth()
        tracker.recordFinishedEvent(
            store: .classroomShare, type: .export, succeeded: false, error: productionSchemaRejection()
        )
        let failure = try #require(tracker.mostSevereFailure)

        #expect(health(storeFailure: failure) == .error(failure.message))
        #expect(health(storeFailure: failure, isSyncing: true) == .error(failure.message))
        #expect(health(storeFailure: nil) == .healthy)
    }

    @Test("A retrying store is a warning, not healthy")
    func retryingStoreIsWarning() throws {
        var tracker = CloudKitStoreHealth()
        tracker.recordFinishedEvent(
            store: .notebook, type: .export, succeeded: false, error: ckError(.networkFailure, "Lost")
        )
        let failure = try #require(tracker.mostSevereFailure)
        #expect(health(storeFailure: failure) == .warning)
    }
}

// MARK: - Through the service and sync_status

@Suite("Sync status: per-store health through the service", .serialized)
@MainActor
struct CloudKitStoreHealthServiceTests {

    private let keys = [
        UserDefaultsKeys.cloudKitLastSuccessfulSyncDate,
        UserDefaultsKeys.cloudKitLastSyncError,
        UserDefaultsKeys.cloudKitLastSyncErrorDetail,
        UserDefaultsKeys.cloudKitLastSyncErrorKind,
        UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate,
        UserDefaultsKeys.cloudKitErrorLog,
        UserDefaultsKeys.cloudKitLastErrorDescription
    ]

    private func withSavedDefaults(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        try body()
    }

    private func makeService() -> CloudKitSyncStatusService {
        let service = CloudKitSyncStatusService()
        service.syncedStoreResolver = { identifier in
            SyncedStore(
                identifier: identifier, notebookIdentifier: "private-store", classroomShareIdentifier: "shared-store"
            )
        }
        return service
    }

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

    @Test("The 2026-09-30 incident: the classroom share stays failed while the notebook syncs")
    func incidentReplay() throws {
        try withSavedDefaults {
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }

            finish(service, .export, store: "shared-store", error: productionSchemaRejection())
            finish(service, .export, store: "private-store")

            // The old global error is gone — which is exactly what hid this before.
            #expect(service.lastSyncError == nil)
            let failure = try #require(service.storeHealth.mostSevereFailure)
            #expect(failure.store == .classroomShare)
            #expect(failure.severity == .stopped)

            let text = MCPNotebookTools.describeSyncStatus(service)
            #expect(text.contains("Classroom share: NOT SYNCING"))
            #expect(text.contains("\u{201C}\(schemaMessage)\u{201D} (CKError 12)"))
            #expect(text.contains("Notebook: OK, last synced"))
            #expect(!text.contains("Sync: healthy"))

            finish(service, .export, store: "shared-store")
            #expect(service.storeHealth.mostSevereFailure == nil)
            #expect(MCPNotebookTools.describeSyncStatus(service).contains("Classroom share: OK, last synced"))
        }
    }

    @Test("After the refusal the delegate dies; sync_status blames the schema, not this device's copy")
    func deadDelegateAfterRefusal() {
        withSavedDefaults {
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            finish(service, .export, store: "shared-store", error: productionSchemaRejection())
            let aborted = NSError(domain: NSCocoaErrorDomain, code: 134_406, userInfo: [
                NSLocalizedDescriptionKey: "The request was aborted because the mirroring delegate "
                    + "never successfully initialized."
            ])
            finish(service, .export, store: "shared-store", error: aborted)
            #expect(service.mirroringDelegateFailed)

            // sync_status goes to Claude, so it carries the details (the server's words, the fix).
            let text = MCPNotebookTools.describeSyncStatus(service)
            #expect(text.contains("WARNING: Classroom sync is stopped."))
            #expect(text.contains("deploy the CloudKit schema to Production"))
            #expect(text.contains("\u{201C}\(schemaMessage)\u{201D} (CKError 12)"))
            #expect(!text.contains("damaged"))
        }
    }

    @Test("A failure's global error is plain; its detail names its store")
    func globalErrorNamesStore() {
        withSavedDefaults {
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            finish(service, .export, store: "shared-store", error: productionSchemaRejection())
            #expect(service.lastSyncErrorDetail?.hasPrefix("Classroom share export failed") == true)
            #expect(service.lastSyncError?.contains("CKError") == false)
            #expect(service.lastSyncError?.contains("failed") == false)
        }
    }
}
