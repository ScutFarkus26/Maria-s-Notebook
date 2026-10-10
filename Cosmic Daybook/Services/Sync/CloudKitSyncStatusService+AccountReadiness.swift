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
// - No account signed in at all (CloudKit's account status says `noAccount`,
//   asked once at once and again after the account changes or a minute):
//   until the app is reopened (`shareFilingPausedUntilReopen`). The notebook
//   never rebuilds its stack, and Apple documents no recovery (Danny's call).
//   Asked only once, a Mac opening at login latched this on an account still
//   signing in (bug hunt 2026-10-10, #4).
// - An account signed in but not ready yet (the Mac app opening at login):
//   only until it is. Core Data sets the store up again once the account is
//   ready (TN3164), so the hold lifts by itself once that store's setup has
//   succeeded and a successful import or export has followed it, or once an
//   import of that store that began after the failed setup has succeeded
//   (Core Data may never post another setup: 2026-10-10, #4).
//   Until the 2026-10-09 review this case paused filing until quit too, so a
//   Mac left open all day never shared.
// - A setup of the notebook's private store, the one filing goes through,
//   that failed for the network, a busy or throttled server, or with no
//   error at all (bug hunt 2026-10-10, #2): held the same way. Such a
//   failure doesn't mark the delegate dead, so before this it held nothing,
//   and the next save's pass filed into a store that never set up.

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
    /// It is shown only when no account was signed in; it used to say iCloud
    /// "wasn't ready", and reopening without signing in brought it straight
    /// back (bug hunt 2026-10-10, #7).
    nonisolated static let shareFilingPausedMessage = "You weren't signed in to iCloud when the notebook opened. "
        + "Sign in to iCloud, then quit and reopen the notebook."

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

    /// Why nothing may be filed into the classroom share now, as a phrase
    /// that finishes "…couldn't be added because …", or nil. An attach pass
    /// asks before each call to CloudKit (`ClassroomShareAttach.Steps`), so a
    /// stop or a hold that starts mid-pass ends it (bug hunt 2026-10-10, #6).
    var shareFilingStopReason: String? {
        if mirroringDelegateFailed { return "iCloud stopped syncing" }
        switch shareFilingHold {
        case .untilReopen: return "you weren't signed in to iCloud when the notebook opened"
        case .untilICloudReady: return "iCloud isn't ready yet"
        case nil: return nil
        }
    }

    /// `shareFilingStopReason` of the shared service, for an attach pass to
    /// ask from off the main actor.
    static let sharedFilingStopReason: @Sendable () async -> String? = { @MainActor in
        CloudKitSyncStatusService.shared.shareFilingStopReason
    }

    /// Follows one finished event for the holds, by its store identifier: a
    /// setup that failed for want of an account, or for a reason Core Data
    /// retries, lists the store (`accountNotReadyStores`); that store's next
    /// successful setup, then its next successful import or export, take it
    /// off again, as does an import of it that began after the failed setup.
    /// Called from `receive` only, as each event arrives.
    func followAccountReadiness(_ event: CloudKitEventValues) {
        guard event.isFinished else { return }
        let storeKey = event.storeIdentifier ?? ""
        guard event.succeeded else {
            if event.type == .setup { followFailedSetup(event, storeKey: storeKey) }
            return
        }
        guard let readiness = accountNotReadyStores[storeKey] else { return }
        switch event.type {
        case .setup:
            if readiness == .awaitingSetup { accountNotReadyStores[storeKey] = .awaitingSync }
        case .import, .export:
            // Set up and synced since; or no setup event came back, but the
            // store imported in an event that began after its setup failed.
            let importedSinceFailure = event.type == .import
                && setupFailedAt[storeKey].map { event.startDate > $0 } == true
            if readiness == .awaitingSync || importedSinceFailure { liftHold(storeKey: storeKey) }
        default:
            break
        }
    }

    /// A failed setup: for want of an account, the store is held. For a
    /// reason Core Data runs setup again for (the network, a busy or
    /// throttled server, no error at all), only the notebook's private store
    /// is: the guide's filing goes through it alone. His classroom-share
    /// store is empty, and may never set up again this session, so holding
    /// it held his filing until relaunch (2026-10-10 review, #3). One that
    /// marks the delegate dead (`marksMirroringDead`) is the stopped flag's.
    private func followFailedSetup(_ event: CloudKitEventValues, storeKey: String) {
        if let error = event.error, CloudKitStoreHealth.isAccountUnavailable(error) {
            noteSetupWithoutAccount(storeKey: storeKey, error: error, startedAt: event.startDate)
        } else if event.error.map(CloudKitStoreHealth.isAccountOrNetworkFailure) ?? true,
                  syncedStore(forIdentifier: event.storeIdentifier) == .notebook {
            holdFilingUntilSetUp(storeKey: storeKey, startedAt: event.startDate, because: "the network or server")
        }
    }

    /// `storeKey` set up and synced again: off the list, and once nothing
    /// holds filing, what waited goes in.
    private func liftHold(storeKey: String) {
        accountNotReadyStores[storeKey] = nil
        setupFailedAt[storeKey] = nil
        guard shareFilingHold == nil else { return }
        Self.logger.notice("iCloud is ready: filing into the classroom share resumes")
        SyncEventLogger.shared.log(
            "cloudkit", status: "success", message: "iCloud is ready. Sharing has picked up again."
        )
        // What waited goes in now, rather than at the next save or remote change.
        filingHooks.wakeFiling()
    }

    /// A store's setup failed in a way Core Data runs again: filing waits for
    /// that store to set up and sync.
    private func holdFilingUntilSetUp(storeKey: String, startedAt start: Date, because reason: String) {
        let wasHeld = shareFilingHold != nil
        accountNotReadyStores[storeKey] = .awaitingSetup
        setupFailedAt[storeKey] = max(setupFailedAt[storeKey] ?? start, start)
        guard !wasHeld else { return }
        Self.logger.notice("CloudKit setup failed for \(reason, privacy: .public): classroom share filing waits")
        SyncEventLogger.shared.log("cloudkit", status: "error", message: Self.shareFilingWaitsForICloudMessage)
    }

    /// A store's setup failed for want of an account: filing waits for it at
    /// once. Unless the error itself says the account is only not ready yet,
    /// CloudKit's account status decides whether there is one at all: asked
    /// now and, if it says none, again once the account changes or a minute
    /// has passed. Only if it still says none, and the store hasn't set up
    /// since, does filing pause until the app is reopened. One `noAccount`
    /// read right at login latched the pause on an account still signing in
    /// (bug hunt 2026-10-10, #4).
    private func noteSetupWithoutAccount(storeKey: String, error: any Error, startedAt start: Date) {
        holdFilingUntilSetUp(storeKey: storeKey, startedAt: start, because: "want of a ready iCloud account")
        guard !CloudKitStoreHealth.isAccountNotReadyYet(error) else { return }
        Task { [weak self] in
            guard let self, await self.stillNoAccount(storeKey: storeKey) else { return }
            await self.filingHooks.waitBeforeAccountRecheck()
            guard await self.stillNoAccount(storeKey: storeKey) else { return }
            self.shareFilingPausedUntilReopen = true
            Self.logger.notice("No iCloud account is signed in: classroom share filing waits for a relaunch")
            SyncEventLogger.shared.log("cloudkit", status: "error", message: Self.shareFilingPausedMessage)
        }
    }

    /// True when CloudKit says no account is signed in, `storeKey` hasn't set
    /// up since its setup failed, and filing isn't paused already.
    private func stillNoAccount(storeKey: String) async -> Bool {
        guard let status = try? await accountStatus() else { return false }
        return status == .noAccount && accountNotReadyStores[storeKey] == .awaitingSetup
            && !shareFilingPausedUntilReopen
    }

    /// Returns at the next `CKAccountChanged`, or after `limit`, whichever
    /// comes first. CloudKit posts the notice on a queue of its own, and
    /// only once a container exists (`CloudKitConfigurationService.container`).
    static func accountChangeOrTimeout(_ limit: Duration) async {
        _ = CloudKitConfigurationService.container
        let signal = AccountRecheckSignal()
        let observer = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { signal.fire() }
        }
        let timer = Task {
            try? await Task.sleep(for: limit)
            signal.fire()
        }
        await signal.wait()
        timer.cancel()
        NotificationCenter.default.removeObserver(observer)
    }
}

/// How the sync status reaches the orphan guard, and how long it waits before
/// asking about the account again. The real ones by default; a test sets its own.
struct ShareFilingHooks {
    /// The wait between the two account checks after a setup failed for want
    /// of an account: until the account changes, or a minute.
    var waitBeforeAccountRecheck: @MainActor () async -> Void = {
        await CloudKitSyncStatusService.accountChangeOrTimeout(.seconds(60))
    }

    /// Sets the orphan guard's pass going once sync lets it file again: a
    /// stop cleared, a hold lifted, or the import a pin from another device
    /// waited for (bug hunt 2026-10-10, #5).
    var wakeFiling: @MainActor () -> Void = {
        SharedStoreOrphanGuard.shared.flushPendingIfPossible()
    }

    /// Whether the orphan guard waits for an import into the notebook since a
    /// pin from another device arrived.
    var waitsForImportAfterPin: @MainActor () -> Bool = {
        SharedStoreOrphanGuard.shared.isWaitingForImportAfterPin
    }
}

/// Resumes the one waiter once, whichever comes first: the account changing
/// or the time running out.
private final class AccountRecheckSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func wait() async {
        guard !fired else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func fire() {
        guard !fired else { return }
        fired = true
        continuation?.resume()
        continuation = nil
    }
}
