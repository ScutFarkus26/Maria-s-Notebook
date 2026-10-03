import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - iCloud sync in plain English
//
// What Settings, the toolbar dot and Sync History show about sync says what
// happened and what to do. The server's words, error domains and codes are
// kept beside the message (`details`, `lastSyncErrorDetail`, a history row's
// `detail`) for the Details disclosure and `sync_status`, never in it.

/// Words that mean raw system text leaked into a message.
private let rawMarkers = ["CKError", "NSCocoaErrorDomain", "CKErrorDomain", "Domain", "[", "\u{201C}", "failed:"]

private func expectPlain(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!message.isEmpty, sourceLocation: sourceLocation)
    for marker in rawMarkers {
        #expect(!message.contains(marker), "\"\(message)\" contains \(marker)", sourceLocation: sourceLocation)
    }
}

private func ckError(_ code: CKError.Code, _ message: String) -> NSError {
    NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
}

private let schemaRefusal = NSError(domain: CKErrorDomain, code: CKError.Code.invalidArguments.rawValue, userInfo: [
    NSLocalizedDescriptionKey: "Invalid Arguments",
    "ServerErrorDescription": "Cannot create new type CD_AttendanceEmailSettings in production schema"
])

private let deadDelegate = NSError(domain: NSCocoaErrorDomain, code: 134_406, userInfo: [
    NSLocalizedDescriptionKey: "The request was aborted because the mirroring delegate never successfully initialized."
])

@Suite("Sync status: plain-English messages")
@MainActor
struct SyncPlainEnglishTests {

    // MARK: A store's failure

    @Test("A stopped store's message names the part and the direction; the server's words are in details")
    func stoppedStoreMessage() throws {
        var health = CloudKitStoreHealth()
        health.recordFinishedEvent(store: .classroomShare, type: .export, succeeded: false, error: schemaRefusal)
        let failure = try #require(health.mostSevereFailure)
        #expect(failure.message
            == "The classroom share can't send changes to iCloud right now. Your changes are safe on this device.")
        expectPlain(failure.message)
        #expect(failure.details.hasPrefix("Classroom share export failed"))
        #expect(failure.details.contains("production schema"))
        #expect(failure.details.contains("CKError 12"))
    }

    @Test("A retrying store's message adds that iCloud will try again")
    func retryingStoreMessage() throws {
        var health = CloudKitStoreHealth()
        health.recordFinishedEvent(
            store: .notebook, type: .import, succeeded: false, error: ckError(.networkFailure, "Lost")
        )
        let failure = try #require(health.mostSevereFailure)
        #expect(failure.message == "Your notebook can't get changes from iCloud right now. "
            + "Your changes are safe on this device. iCloud will try again.")
        expectPlain(failure.message)
    }

    // MARK: The shown error

    @Test("A failed event's error is translated for iCloud and the network, general otherwise")
    func eventFailureMessages() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let quota = ckError(.quotaExceeded, "Quota exceeded")
        for error in [offline, quota, deadDelegate, schemaRefusal] {
            expectPlain(CloudKitSyncStatusService.plainEventFailureMessage(for: error, type: .export))
        }
        #expect(CloudKitSyncStatusService.plainEventFailureMessage(for: quota, type: .export)
            == "Your iCloud storage is full. Free up space so your notebook can keep syncing.")
        #expect(CloudKitSyncStatusService.plainEventFailureMessage(for: deadDelegate, type: .export)
            == "iCloud sync didn't finish. It'll try again on its own.")
        #expect(CloudKitSyncStatusService.plainEventFailureMessage(for: nil, type: .setup)
            == "iCloud sync couldn't start. Reopen the app to try again.")
    }

    @Test("Errors are sorted into network, account and everything else, looking inside wrappers")
    func errorKinds() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
            NSUnderlyingErrorKey: ckError(.networkUnavailable, "No network")
        ])
        #expect(CloudKitSyncStatusService.errorKind(of: offline) == .network)
        #expect(CloudKitSyncStatusService.errorKind(of: wrapped) == .network)
        #expect(CloudKitSyncStatusService.errorKind(of: ckError(.notAuthenticated, "Signed out")) == .account)
        #expect(CloudKitSyncStatusService.errorKind(of: deadDelegate) == .other)
    }

    // MARK: Sync History lines

    @Test("Sync History's lines say what happened, not the event's name")
    func historyLines() {
        #expect(CloudKitSyncStatusService.historyLine(succeeded: .export) == "Sent changes to iCloud")
        #expect(CloudKitSyncStatusService.historyLine(succeeded: .import) == "Got changes from iCloud")
        #expect(CloudKitSyncStatusService.historyLine(succeeded: .setup) == "iCloud sync started")
        #expect(CloudKitSyncStatusService.historyLine(failed: .export, store: .notebook, stopped: false)
            == "Couldn't send changes \u{2014} will try again")
        #expect(CloudKitSyncStatusService.historyLine(failed: .import, store: .classroomShare, stopped: true)
            == "Couldn't get classroom share changes from iCloud \u{2014} sync is stopped")
        #expect(CloudKitSyncStatusService.historyLine(failed: .setup, store: .classroomShare, stopped: true)
            == "Classroom share sync couldn't start")
    }
}

// MARK: - Through the service

@Suite("Sync status: the shown error through the service", .serialized)
@MainActor
struct SyncShownErrorServiceTests {

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

    @Test("A failed export shows plain words, keeps the raw form as the detail, and persists both")
    func failedEventShownAndDetail() throws {
        try withSavedDefaults {
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            service.handleCloudKitEvent(
                type: .export, isFinished: true, succeeded: false,
                error: ckError(.networkFailure, "The network connection was lost"),
                startDate: Date(), storeIdentifier: "private-store"
            )
            let shown = try #require(service.lastSyncError)
            expectPlain(shown)
            #expect(service.lastSyncErrorKind == .network)
            let detail = try #require(service.lastSyncErrorDetail)
            #expect(detail.hasPrefix("Notebook export failed [CKErrorDomain (4)]"))
            #expect(detail.contains("The network connection was lost"))

            let defaults = UserDefaults.standard
            #expect(defaults.string(forKey: UserDefaultsKeys.cloudKitLastSyncError) == shown)
            #expect(defaults.string(forKey: UserDefaultsKeys.cloudKitLastSyncErrorDetail) == detail)
            #expect(defaults.string(forKey: UserDefaultsKeys.cloudKitLastSyncErrorKind) == "network")

            // Coming back online clears a network problem by its kind, not its wording.
            service.handleNetworkChange(isAvailable: true)
            #expect(service.lastSyncError == nil)
            #expect(service.lastSyncErrorDetail == nil)
            #expect(defaults.object(forKey: UserDefaultsKeys.cloudKitLastSyncErrorDetail) == nil)
        }
    }

    @Test("Signing in leaves a problem that isn't about the account")
    func signInKeepsOtherProblems() {
        withSavedDefaults {
            let service = makeService()
            service.recordSyncError("iCloud sync didn't finish. It'll try again on its own.", detail: "x", kind: .other)
            service.handleICloudAccountChange(isAvailable: true)
            #expect(service.lastSyncError != nil)
            service.recordSyncError("Sign in", detail: nil, kind: .account)
            service.handleICloudAccountChange(isAvailable: true)
            #expect(service.lastSyncError == nil)
            service.clearError()
        }
    }

    @Test("An error saved by an older build reads as plain words, with its old text as the detail")
    func legacyStoredErrorReadsPlain() {
        withSavedDefaults {
            let defaults = UserDefaults.standard
            let raw = "Classroom share export failed [CKErrorDomain (2)]: Failed to modify some records"
            defaults.set(raw, forKey: UserDefaultsKeys.cloudKitLastSyncError)
            defaults.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncErrorDetail)
            defaults.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncErrorKind)

            let service = CloudKitSyncStatusService()
            #expect(service.lastSyncError == "iCloud sync didn't finish. It'll try again on its own.")
            #expect(service.lastSyncErrorDetail == raw)

            let offline = "Changes saved locally. Waiting for network to sync."
            defaults.set(offline, forKey: UserDefaultsKeys.cloudKitLastSyncError)
            #expect(CloudKitSyncStatusService().lastSyncErrorKind == .network)
            CloudKitSyncStatusService.removePersistedSyncError()
        }
    }

    @Test("sync_status reads the raw detail; Settings' error stays plain")
    func syncStatusReadsDetail() {
        withSavedDefaults {
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            service.handleCloudKitEvent(
                type: .export, isFinished: true, succeeded: false, error: deadDelegate,
                startDate: Date(), storeIdentifier: "private-store"
            )
            let text = MCPNotebookTools.describeSyncStatus(service)
            #expect(text.contains("Last error: Notebook export failed [NSCocoaErrorDomain (134406)]"))
            #expect(service.lastSyncError == "iCloud sync didn't finish. It'll try again on its own.")
            service.clearError()
        }
    }
}

// MARK: - Sync History rows

@Suite("Sync History: plain rows with the raw text as detail")
@MainActor
struct SyncHistoryPlainRowsTests {

    private static let storageKey = "SyncHistory.events.test"

    private struct Fixture {
        let logger: SyncEventLogger
        let defaults: UserDefaults
        let suiteName: String

        func cleanUp() { defaults.removePersistentDomain(forName: suiteName) }
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "sync-history-plain-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let logger = SyncEventLogger(defaults: defaults, storageKey: Self.storageKey, saveDelay: .milliseconds(10))
        return Fixture(logger: logger, defaults: defaults, suiteName: suiteName)
    }

    @Test("A new row shows its message, and its detail under it")
    func newRowWithDetail() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let logger = fixture.logger
        logger.log("cloudkit", status: "error", message: "Couldn't send changes \u{2014} will try again",
                   detail: "Notebook export failed [CKErrorDomain (4)]: Lost")
        let event = try #require(logger.events.first)
        #expect(event.shownMessage == "Couldn't send changes \u{2014} will try again")
        #expect(event.shownDetail == "Notebook export failed [CKErrorDomain (4)]: Lost")
    }

    @Test("Repeats with a different detail stay separate rows")
    func detailSeparatesRows() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let logger = fixture.logger
        logger.log("cloudkit", status: "error", message: "Couldn't send changes", detail: "A")
        logger.log("cloudkit", status: "error", message: "Couldn't send changes", detail: "A")
        logger.log("cloudkit", status: "error", message: "Couldn't send changes", detail: "B")
        #expect(logger.events.map(\.count) == [1, 2])
    }

    @Test("Rows from older builds read in plain words, with the old text as the detail")
    func legacyRows() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let defaults = fixture.defaults
        let legacy = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","timestamp":0,\
        "type":"cloudkit","status":"success","message":"Export completed"},\
        {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","timestamp":0,\
        "type":"cloudkit","status":"error","message":"Notebook export failed [CKErrorDomain (4)]: Lost"},\
        {"id":"8F9619FF-8B86-D011-B42D-00C04FC964FF","timestamp":0,\
        "type":"reminders","status":"error","message":"Reminders access has not been granted."},\
        {"id":"9F9619FF-8B86-D011-B42D-00C04FC964FF","timestamp":0,\
        "type":"calendar","status":"success","message":"Calendar sync completed"}]
        """
        defaults.set(Data(legacy.utf8), forKey: Self.storageKey)
        let events = SyncEventLogger(defaults: defaults, storageKey: Self.storageKey).events
        #expect(events.map(\.shownMessage) == [
            "Sent changes to iCloud", "Couldn't sync with iCloud", "Couldn't sync with Reminders",
            "Calendar sync completed"
        ])
        #expect(events.map(\.shownDetail) == [
            "Export completed", "Notebook export failed [CKErrorDomain (4)]: Lost",
            "Reminders access has not been granted.", nil
        ])
    }
}
