import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - The "iCloud sync is stopped" banner
//
// On 2026-09-30 the classroom share's export was refused by the Production
// schema, then its mirroring delegate logged "never successfully initialized".
// The banner blamed a damaged local copy and suggested "Re-download from
// iCloud…", which could not fix a server refusal and would have thrown away
// the unsent changes. These feed `SyncStoppedAdvice` synthetic failures.

private let schemaMessage = "Cannot create new type CD_AttendanceEmailSettings in production schema"

private func ckError(_ code: CKError.Code, _ message: String? = nil, userInfo: [String: Any] = [:]) -> NSError {
    var info = userInfo
    if let message { info[NSLocalizedDescriptionKey] = message }
    return NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: info)
}

/// The incident's export error: the schema refusal inside a partial failure.
private func productionSchemaRejection() -> NSError {
    let zone = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.share.DB5879EF", ownerName: CKCurrentUserDefaultName
    )
    return ckError(.partialFailure, "Failed to modify some records", userInfo: [
        CKPartialErrorsByItemIDKey: [
            CKRecord.ID(recordName: "a", zoneID: zone): ckError(.batchRequestFailed, "Atomic failure"),
            CKRecord.ID(recordName: "b", zoneID: zone): ckError(
                .invalidArguments, "Invalid Arguments", userInfo: ["ServerErrorDescription": schemaMessage]
            )
        ]
    ])
}

/// What the delegate says after the refusal (and on its own for a damaged store).
private func neverInitialized(_ code: Int = 134_406) -> NSError {
    NSError(domain: NSCocoaErrorDomain, code: code, userInfo: [
        NSLocalizedDescriptionKey: "The request was aborted because the mirroring delegate "
            + "never successfully initialized."
    ])
}

/// One failed event.
private struct Failed {
    let store: SyncedStore
    let type: NSPersistentCloudKitContainer.EventType
    let error: NSError?

    init(_ store: SyncedStore, _ type: NSPersistentCloudKitContainer.EventType, _ error: NSError?) {
        self.store = store
        self.type = type
        self.error = error
    }
}

private let redownload = "\u{201C}Re-download from iCloud\u{2026}\u{201D}"

@Suite("Sync status: the stopped-sync banner")
@MainActor
struct SyncStoppedAdviceTests {

    private func advice(_ events: [Failed]) -> SyncStoppedAdvice {
        var health = CloudKitStoreHealth()
        for event in events {
            health.recordFinishedEvent(store: event.store, type: event.type, succeeded: false, error: event.error)
        }
        return SyncStoppedAdvice.make(health: health)
    }

    // MARK: Server refusals

    @Test("The 2026-09-30 incident: names the classroom share, quotes the schema error, says not to re-download")
    func incident() {
        let advice = advice([
            Failed(.classroomShare, .export, productionSchemaRejection()),
            Failed(.classroomShare, .export, neverInitialized()),
            Failed(.classroomShare, .setup, neverInitialized())
        ])
        #expect(advice.diagnosis == .serverRefusal)
        #expect(advice.store == .classroomShare)
        #expect(!advice.suggestsRedownload)
        #expect(advice.title == "Classroom share sync is stopped")
        #expect(advice.message.contains("the classroom share: \u{201C}\(schemaMessage)\u{201D} (CKError 12)"))
        #expect(advice.message.contains("deploy the CloudKit schema to Production"))
        #expect(advice.message.contains("Your changes are kept on this device"))
        #expect(advice.message.contains("Don't use \(redownload)"))
        #expect(!advice.message.contains("damaged"))
    }

    @Test("The dead delegate that follows a refusal doesn't replace it on the same event kind")
    func refusalIsNotReplacedBySymptoms() throws {
        var health = CloudKitStoreHealth()
        let first = Date(timeIntervalSince1970: 1_000_000)
        health.recordFinishedEvent(
            store: .classroomShare, type: .export, succeeded: false, error: productionSchemaRejection(), at: first
        )
        health.recordFinishedEvent(store: .classroomShare, type: .export, succeeded: false, error: neverInitialized())
        health.recordFinishedEvent(
            store: .classroomShare, type: .export, succeeded: false, error: ckError(.networkFailure, "Lost")
        )
        let failure = try #require(health.failures(for: .classroomShare).first)
        #expect(failure.serverMessage == schemaMessage)
        #expect(failure.cause == .serverRefusal(ckCode: CKError.Code.invalidArguments.rawValue))
        #expect(failure.date == first)

        // A success of that kind still clears it.
        health.recordFinishedEvent(store: .classroomShare, type: .export, succeeded: true, error: nil)
        #expect(health.outstandingFailures.isEmpty)
    }

    @Test("A refusal Core Data wraps in a dead-delegate error is still read as the refusal")
    func wrappedRefusal() {
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_406, userInfo: [
            NSUnderlyingErrorKey: ckError(.serverRejectedRequest, "Server rejected the request")
        ])
        let detail = CloudKitStoreHealth.detail(of: wrapped)
        #expect(detail.cause == .serverRefusal(ckCode: CKError.Code.serverRejectedRequest.rawValue))
        #expect(detail.code == "CKError 15")
    }

    @Test("A refusal on one store outranks a dead delegate on the other: re-downloading would lose its changes")
    func refusalWinsAcrossStores() {
        let advice = advice([
            Failed(.notebook, .export, neverInitialized(134_421)),
            Failed(.classroomShare, .export, productionSchemaRejection())
        ])
        #expect(advice.diagnosis == .serverRefusal)
        #expect(advice.store == .classroomShare)
        #expect(!advice.suggestsRedownload)
    }

    @Test("A full quota names whose storage to free")
    func quota() {
        let share = advice([Failed(.classroomShare, .export, ckError(.quotaExceeded, "Quota exceeded"))])
        #expect(share.diagnosis == .serverRefusal)
        #expect(share.message.contains("free up the share owner's iCloud storage"))
        let notebook = advice([Failed(.notebook, .export, ckError(.quotaExceeded, "Quota exceeded"))])
        #expect(notebook.title == "Notebook sync is stopped")
        #expect(notebook.message.contains("free up iCloud storage"))
    }

    @Test("A permission failure on the share asks about iCloud sign-in and classroom membership")
    func permission() {
        let advice = advice([Failed(.classroomShare, .import, ckError(.permissionFailure, "Permission failure"))])
        #expect(advice.diagnosis == .serverRefusal)
        #expect(advice.message.contains("signed in to iCloud and still a member of the classroom"))
        #expect(advice.message.contains("Don't use \(redownload)"))
    }

    @Test("Any other refusal says the fix is on the iCloud side and quotes the server")
    func otherRefusal() {
        let rejected = ckError(.serverRejectedRequest, "Server rejected the request")
        let advice = advice([Failed(.notebook, .export, rejected)])
        #expect(advice.diagnosis == .serverRefusal)
        #expect(advice.message.contains("\u{201C}Server rejected the request\u{201D} (CKError 15)"))
        #expect(advice.message.contains("The fix is on the iCloud side, not on this device"))
        #expect(!advice.suggestsRedownload)
    }

    // MARK: A damaged local copy

    @Test("134421 or 134406 with no refusal on the store suggests Re-download, naming the store")
    func damagedLocalStore() {
        for code in [134_421, 134_406] {
            let advice = advice([Failed(.notebook, .export, neverInitialized(code))])
            #expect(advice.diagnosis == .damagedLocalStore)
            #expect(advice.store == .notebook)
            #expect(advice.suggestsRedownload)
            #expect(advice.title == "Notebook sync is stopped")
            #expect(advice.message.contains("this device's copy of the notebook is damaged"))
            #expect(advice.message.contains(redownload))
        }
    }

    @Test("A retrying failure elsewhere doesn't change a damaged-store diagnosis")
    func retryingElsewhere() {
        let advice = advice([
            Failed(.classroomShare, .export, ckError(.networkFailure, "Lost")),
            Failed(.classroomShare, .setup, neverInitialized())
        ])
        #expect(advice.diagnosis == .damagedLocalStore)
        #expect(advice.store == .classroomShare)
    }

    @Test("With nothing recorded (the flag came from attaching records to the share) it keeps the old advice")
    func nothingRecorded() {
        let advice = SyncStoppedAdvice.make(health: CloudKitStoreHealth())
        #expect(advice.diagnosis == .damagedLocalStore)
        #expect(advice.store == nil)
        #expect(advice.title == "iCloud sync is stopped")
        #expect(advice.message.contains("copy of your notebook is damaged"))
    }

    // MARK: Anything else

    @Test("A setup failure for another reason quotes it and suggests reopening, not re-downloading")
    func otherSetupFailure() {
        let advice = advice([Failed(.notebook, .setup, ckError(.networkFailure, "The network connection was lost"))])
        #expect(advice.diagnosis == .other)
        #expect(!advice.suggestsRedownload)
        #expect(advice.message.contains("\u{201C}The network connection was lost\u{201D} (CKError 4)"))
        #expect(advice.message.contains("Reopen the app"))
    }

    @Test("A setup failure with no error quotes nothing")
    func setupFailureWithoutError() {
        let advice = advice([Failed(.classroomShare, .setup, nil)])
        #expect(advice.diagnosis == .other)
        #expect(advice.message.hasPrefix("iCloud couldn't start syncing the classroom share. "))
        #expect(!advice.message.contains(StoreSyncFailure.noErrorCode))
    }
}
