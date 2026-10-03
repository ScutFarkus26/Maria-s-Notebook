import CloudKit
import Foundation

// MARK: - What to say when sync has stopped
//
// `CloudKitSyncStatusService.mirroringDelegateFailed` says a mirroring delegate
// died this session, not why. The banner used to blame a damaged local copy
// and send the guide to "Re-download from iCloud…" whichever store failed. On
// 2026-09-30 the classroom share stopped because the Production schema refused
// its export ("Cannot create new type CD_AttendanceEmailSettings in production
// schema"); re-downloading could not have fixed that and would have thrown away
// the changes waiting to send. The per-store failures say which it is.

/// The "iCloud sync is stopped" banner's diagnosis and copy.
nonisolated struct SyncStoppedAdvice: Equatable, Sendable {
    enum Diagnosis: Equatable, Sendable {
        /// iCloud refused the store's requests. The fix is on the iCloud side;
        /// this device's copy is fine and keeps its unsent changes.
        case serverRefusal
        /// The store's mirroring delegate died with no refusal behind it: this
        /// device's copy is damaged or unreadable. Re-download fixes it.
        case damagedLocalStore
        /// Setup failed for some other reason (or with no error).
        case other
    }

    let diagnosis: Diagnosis
    /// The store that stopped; nil when nothing this session says which (the
    /// flag can come from attaching records to the share, which has no store).
    let store: SyncedStore?
    let title: String
    /// What happened and what to do, in plain words.
    let message: String
    /// What the server said and the developer-side fix, for the Details
    /// disclosure and `sync_status`. Empty when there's nothing to add.
    let details: String

    /// Only a damaged local copy is fixed by re-downloading.
    var suggestsRedownload: Bool { diagnosis == .damagedLocalStore }

    /// Decides from the outstanding failures. A refusal on any store wins: it
    /// is the one case where re-downloading does harm. Then a dead delegate,
    /// then any other stopped failure. With none recorded, the flag's other
    /// sources (attaching records to the classroom share) set it only for a
    /// dead delegate, so that reads as a damaged copy of an unnamed store.
    static func make(health: CloudKitStoreHealth) -> SyncStoppedAdvice {
        let stopped = health.outstandingFailures.filter { $0.severity == .stopped }
        if let refusal = stopped.first(where: { $0.cause.isServerRefusal }) {
            return serverRefusal(refusal)
        }
        if let dead = stopped.first(where: { $0.cause == .mirroringDelegateDied }) {
            return damaged(store: dead.store, failure: dead)
        }
        if let other = stopped.first {
            return otherFailure(other)
        }
        return damaged(store: nil, failure: nil)
    }

    // MARK: - Copy

    private static func title(for store: SyncedStore?) -> String {
        switch store {
        case .notebook: return "Notebook sync is stopped"
        case .classroomShare: return "Classroom sync is stopped"
        case .other, nil: return "iCloud sync is stopped"
        }
    }

    /// "the classroom share", "your notebook": mid-sentence, in plain words.
    private static func plainPhrase(_ store: SyncedStore) -> String {
        switch store {
        case .notebook: return "your notebook"
        case .classroomShare: return "the classroom share"
        case .other: return "part of your notebook"
        }
    }

    private static let redownloadWarning = "Don't use \u{201C}Re-download from iCloud\u{2026}\u{201D} for this: "
        + "it can't fix it, and it would throw away the changes waiting to send."

    private static func serverRefusal(_ failure: StoreSyncFailure) -> SyncStoppedAdvice {
        let what = plainPhrase(failure.store)
        let reason: String
        let after: String
        switch refusalKind(failure) {
        case .storageFull:
            let whose = failure.store == .classroomShare ? "the share owner's" : "your"
            reason = "because \(whose) iCloud storage is full"
            after = "Free up iCloud storage, then reopen the app."
        case .signIn:
            let member = failure.store == .classroomShare ? " and still a member of the classroom" : ""
            reason = "because iCloud didn't accept this device"
            after = "Check that this device is signed in to iCloud\(member), then reopen the app."
        case .iCloudSide:
            reason = "because of a problem on iCloud's end"
            after = "An app update may be needed."
        }
        let message = "Sync for \(what) is stopped \(reason). Your changes are kept on this device and will "
            + "send once it's fixed. \(after) \(redownloadWarning)"
        let details = "iCloud refused to sync \(failure.store.phrase): \(quote(failure)). "
            + developerFix(for: failure)
        return SyncStoppedAdvice(
            diagnosis: .serverRefusal, store: failure.store, title: title(for: failure.store),
            message: message, details: details
        )
    }

    private enum RefusalKind { case storageFull, signIn, iCloudSide }

    private static func refusalKind(_ failure: StoreSyncFailure) -> RefusalKind {
        guard case .serverRefusal(let rawCode) = failure.cause,
              failure.serverMessage.range(of: "schema", options: .caseInsensitive) == nil
        else { return .iCloudSide }
        switch CKError.Code(rawValue: rawCode) {
        case .quotaExceeded: return .storageFull
        case .permissionFailure, .notAuthenticated, .participantMayNeedVerification, .managedAccountRestricted:
            return .signIn
        default: return .iCloudSide
        }
    }

    private static func quote(_ failure: StoreSyncFailure) -> String {
        "\u{201C}\(failure.serverMessage)\u{201D} (\(failure.errorCode))"
    }

    /// What to change on the iCloud side, by what the server said: for the
    /// developer, so it lives in `details`.
    private static func developerFix(for failure: StoreSyncFailure) -> String {
        guard case .serverRefusal(let rawCode) = failure.cause else { return "" }
        if failure.serverMessage.range(of: "schema", options: .caseInsensitive) != nil {
            return "The fix is on the iCloud side: deploy the CloudKit schema to Production in CloudKit "
                + "Console, then reopen the app."
        }
        switch CKError.Code(rawValue: rawCode) {
        case .quotaExceeded:
            let whose = failure.store == .classroomShare ? "the share owner's iCloud storage" : "iCloud storage"
            return "The fix is on the iCloud side: free up \(whose), then reopen the app."
        case .permissionFailure, .notAuthenticated, .participantMayNeedVerification, .managedAccountRestricted:
            let member = failure.store == .classroomShare ? " and still a member of the classroom" : ""
            return "The fix is on the iCloud side: check that this device is signed in to iCloud\(member), "
                + "then reopen the app."
        default:
            return "The fix is on the iCloud side, not on this device; reopen the app once it's sorted out."
        }
    }

    private static func damaged(store: SyncedStore?, failure: StoreSyncFailure?) -> SyncStoppedAdvice {
        let what = store.map { "syncing \($0.phrase)" } ?? "syncing this time"
        let copy = store.map { "copy of \($0.phrase)" } ?? "copy of your notebook"
        let message = "iCloud couldn't start \(what), most likely because this device's \(copy) is "
            + "damaged. To fix it, open Troubleshooting and \(PlatformVerb.tapLowercased) "
            + "\u{201C}Re-download from iCloud\u{2026}\u{201D} Your notebook is safe in iCloud and "
            + "downloads again on its own."
        return SyncStoppedAdvice(
            diagnosis: .damagedLocalStore, store: store, title: title(for: store),
            message: message, details: failure?.details ?? ""
        )
    }

    private static func otherFailure(_ failure: StoreSyncFailure) -> SyncStoppedAdvice {
        let message = "iCloud couldn't start syncing \(plainPhrase(failure.store)). Your changes are kept "
            + "on this device. Reopen the app to try again; if it stops again, open Troubleshooting."
        let details = failure.errorCode == StoreSyncFailure.noErrorCode ? "" : failure.details
        return SyncStoppedAdvice(
            diagnosis: .other, store: failure.store, title: title(for: failure.store),
            message: message, details: details
        )
    }
}
