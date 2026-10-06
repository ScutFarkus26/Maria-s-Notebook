import CoreData
import Foundation
import OSLog

// MARK: - Automatic retries
//
// A retry used to call Sync Now: it saved an empty context, cleared the shown
// error, stamped "Last synced: just now" and logged "You tapped Sync Now",
// though nobody had and nothing had gone. It now only commits unsaved edits
// so the container has them to send. Whether sync worked is said by iCloud's
// own import and export events, nothing else.

extension CloudKitSyncStatusService {

    /// Schedules a retry with exponential backoff (delegated to SyncRetryLogic).
    func scheduleRetry() {
        retryLogic.scheduleRetry(
            canRetry: { [weak self] in
                guard let self else { return false }
                return self.isNetworkAvailable
            },
            syncAction: { [weak self] in
                guard let self else { return false }
                return await self.retrySync()
            },
            onMaxRetriesReached: { [weak self] in
                Task { [weak self] in
                    self?.reportRetriesExhausted()
                }
            }
        )
    }

    /// Called when the network or the iCloud account comes back, to retry at once.
    func retryPendingSync() {
        retryLogic.retryPendingSync(
            canRetry: { [weak self] in
                guard let self else { return false }
                return self.isNetworkAvailable
            },
            hasPendingWork: { [weak self] in
                guard let self else { return false }
                return self.lastSyncError != nil || self.pendingSyncCount > 0
            },
            syncAction: { [weak self] in
                _ = await self?.retrySync()
            }
        )
    }

    /// One automatic retry: commits any unsaved edits so iCloud has them to
    /// send. Not Sync Now: it logs no tap, clears no error and stamps no
    /// sync. Returns false only when the save failed.
    func retrySync() async -> Bool {
        guard let viewContext = coreDataStack?.viewContext else { return false }
        guard viewContext.hasChanges else { return true }
        do {
            try viewContext.save()
            return true
        } catch {
            Self.logger.error("Sync retry couldn't save: \(Self.technicalDetail(of: error), privacy: .public)")
            return false
        }
    }
}
