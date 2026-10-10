import CloudKit
import CoreData
import Foundation
import OSLog

// MARK: - The iCloud account at setup
//
// `container.share(_:to:)` against a store whose CloudKit setup failed can
// raise an exception no Swift `catch` traps, so a setup that fails for want of
// an iCloud account holds filing into the classroom share (bug hunt
// 2026-10-09, #2):
// - No account signed in at all (CloudKit's account status says `noAccount`):
//   until the app is reopened (`shareFilingPausedUntilReopen`). The notebook
//   never rebuilds its stack, and Apple documents no recovery (Danny's call).
// - An account signed in but not ready yet (the Mac app opening at login):
//   only until it is. Core Data sets the store up again once the account is
//   ready (TN3164), so the hold lifts by itself once that store's setup has
//   succeeded and a successful import or export has followed it. Until the
//   2026-10-09 review this case paused filing until quit too, so a Mac left
//   open all day never shared.

extension CloudKitSyncStatusService {

    /// How far a store set up without its iCloud account has come back.
    enum AccountReadiness: Equatable {
        case awaitingSetup
        case awaitingSync
    }

    /// Why iCloud's account holds filing into the classroom share, and what
    /// the sync status says.
    enum ShareFilingHold: Equatable {
        /// No iCloud account when the notebook opened: until it is reopened.
        case untilReopen
        /// The account wasn't ready yet: until its stores have set up and synced.
        case untilICloudReady

        var message: String {
            switch self {
            case .untilReopen: return CloudKitSyncStatusService.shareFilingPausedMessage
            case .untilICloudReady: return CloudKitSyncStatusService.shareFilingWaitsForICloudMessage
            }
        }
    }

    /// What the sync status says while `shareFilingPausedUntilReopen` holds.
    nonisolated static let shareFilingPausedMessage =
        "iCloud wasn't ready when the notebook opened. Quit and reopen it to finish sharing."

    /// What the sync status says while the account isn't ready yet.
    nonisolated static let shareFilingWaitsForICloudMessage = "iCloud isn't ready yet. Sharing will pick up once it is."

    /// Why iCloud's account holds filing into the classroom share, or nil.
    /// Every attach path checks it, beside `mirroringDelegateFailed`: Set Up
    /// Classroom Sharing, the orphan guard, the attendance catch-up and Remove
    /// Last Year.
    var shareFilingHold: ShareFilingHold? {
        if shareFilingPausedUntilReopen { return .untilReopen }
        return accountNotReadyStores.isEmpty ? nil : .untilICloudReady
    }

    /// Follows one finished event for the account holds, by its store
    /// identifier: a setup that failed for want of an account lists the store
    /// (`accountNotReadyStores`); that store's next successful setup, then its
    /// next successful import or export, take it off again. Called from
    /// `receive` only, as each event arrives.
    func followAccountReadiness(_ event: CloudKitEventValues) {
        guard event.isFinished else { return }
        let storeKey = event.storeIdentifier ?? ""
        guard event.succeeded else {
            guard event.type == .setup, let error = event.error,
                  CloudKitStoreHealth.isAccountUnavailable(error) else { return }
            noteSetupWithoutAccount(storeKey: storeKey, error: error)
            return
        }
        guard let readiness = accountNotReadyStores[storeKey] else { return }
        switch (event.type, readiness) {
        case (.setup, .awaitingSetup):
            accountNotReadyStores[storeKey] = .awaitingSync
        case (.import, .awaitingSync), (.export, .awaitingSync):
            accountNotReadyStores[storeKey] = nil
            guard shareFilingHold == nil else { return }
            Self.logger.notice("iCloud is ready: filing into the classroom share resumes")
            SyncEventLogger.shared.log(
                "cloudkit", status: "success", message: "iCloud is ready. Sharing has picked up again."
            )
            // What waited goes in now, rather than at the next save or remote change.
            SharedStoreOrphanGuard.shared.flushPendingIfPossible()
        default:
            break
        }
    }

    /// A store's setup failed for want of an account: filing waits for it at
    /// once. Unless the error itself says the account is only not ready yet,
    /// CloudKit's account status decides whether there is one at all; with
    /// none, filing pauses until the app is reopened.
    private func noteSetupWithoutAccount(storeKey: String, error: any Error) {
        let wasHeld = shareFilingHold != nil
        accountNotReadyStores[storeKey] = .awaitingSetup
        if !wasHeld {
            Self.logger.notice("CloudKit set up without a ready iCloud account: classroom share filing waits")
            SyncEventLogger.shared.log("cloudkit", status: "error", message: Self.shareFilingWaitsForICloudMessage)
        }
        guard !CloudKitStoreHealth.isAccountNotReadyYet(error) else { return }
        Task { [weak self] in
            guard let self, let status = try? await self.accountStatus() else { return }
            // Not if the store has come back meanwhile, or is already paused.
            guard status == .noAccount, self.accountNotReadyStores[storeKey] != nil,
                  !self.shareFilingPausedUntilReopen else { return }
            self.shareFilingPausedUntilReopen = true
            Self.logger.notice("No iCloud account is signed in: classroom share filing waits for a relaunch")
            SyncEventLogger.shared.log("cloudkit", status: "error", message: Self.shareFilingPausedMessage)
        }
    }
}
