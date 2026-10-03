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
    let message: String

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
            return damaged(store: dead.store)
        }
        if let other = stopped.first {
            return otherFailure(other)
        }
        return damaged(store: nil)
    }

    // MARK: - Copy

    private static func title(for store: SyncedStore?) -> String {
        switch store {
        case .notebook: return "Notebook sync is stopped"
        case .classroomShare: return "Classroom share sync is stopped"
        case .other, nil: return "iCloud sync is stopped"
        }
    }

    private static func quote(_ failure: StoreSyncFailure) -> String {
        "\u{201C}\(failure.serverMessage)\u{201D} (\(failure.errorCode))"
    }

    private static func serverRefusal(_ failure: StoreSyncFailure) -> SyncStoppedAdvice {
        let message = "iCloud refused to sync \(failure.store.phrase): \(quote(failure)). "
            + iCloudSideFix(for: failure) + " "
            + "Your changes are kept on this device and send once it's fixed. Don't use "
            + "\u{201C}Re-download from iCloud\u{2026}\u{201D} for this: it can't fix it, "
            + "and it would throw away the changes waiting to send."
        return SyncStoppedAdvice(
            diagnosis: .serverRefusal, store: failure.store, title: title(for: failure.store), message: message
        )
    }

    /// What to change on the iCloud side, by what the server said.
    private static func iCloudSideFix(for failure: StoreSyncFailure) -> String {
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

    private static func damaged(store: SyncedStore?) -> SyncStoppedAdvice {
        let what = store.map { "syncing \($0.phrase)" } ?? "syncing this time"
        let copy = store.map { "copy of \($0.phrase)" } ?? "copy of your notebook"
        let message = "iCloud couldn't start \(what), most likely because this device's \(copy) is "
            + "damaged. To fix it, open Troubleshooting and \(PlatformVerb.tapLowercased) "
            + "\u{201C}Re-download from iCloud\u{2026}\u{201D} Your notebook is safe in iCloud and "
            + "downloads again on its own."
        return SyncStoppedAdvice(
            diagnosis: .damagedLocalStore, store: store, title: title(for: store), message: message
        )
    }

    private static func otherFailure(_ failure: StoreSyncFailure) -> SyncStoppedAdvice {
        let said = failure.errorCode == StoreSyncFailure.noErrorCode ? "" : ": \(quote(failure))"
        let message = "iCloud couldn't start syncing \(failure.store.phrase)\(said). Your changes are kept "
            + "on this device. Reopen the app to try again; if it stops again, open Troubleshooting."
        return SyncStoppedAdvice(
            diagnosis: .other, store: failure.store, title: title(for: failure.store), message: message
        )
    }
}
