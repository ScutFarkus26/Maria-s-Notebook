import Foundation
import SwiftUI
import CoreData
import os

// MARK: - Event Handlers

extension CloudKitSyncStatusService {

    // MARK: - Network & iCloud Change Handlers

    func handleNetworkChange(isAvailable: Bool) {
        if isAvailable {
            // Network restored - clear network-related errors and trigger retry
            let isNetworkError: Bool = lastSyncError?.contains("network") == true
                || lastSyncError?.contains("offline") == true
                || lastSyncError?.contains("Waiting") == true
            if isNetworkError {
                lastSyncError = nil
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
            }
            // Trigger retry for any pending syncs
            retryPendingSync()
        }
        updateSyncHealth()
    }

    func handleICloudAccountChange(isAvailable: Bool) {
        if isAvailable {
            // User signed into iCloud - clear any offline errors and retry
            let isICloudError: Bool = lastSyncError?.contains("iCloud") == true
                || lastSyncError?.contains("signed in") == true
                || lastSyncError?.contains("Sign into") == true
            if isICloudError {
                lastSyncError = nil
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
            }
            // Trigger retry for any pending syncs
            retryPendingSync()
        }
        updateSyncHealth()
    }

    // MARK: - Event Handlers

    func handleStoreCoordinatorChange() {
        // The persistent store coordinator's stores changed.
        // This fires when stores are added/removed — commonly during:
        // 1. Initial CloudKit setup (SwiftData creates temp stores that get torn down)
        // 2. Scene phase transitions on macOS (expected SwiftUI lifecycle)
        // 3. CloudKit mirroring delegate teardown/rebuild
        //
        // Best practice (Apple TN3164): NSCloudKitMirroringDelegate instances are tied
        // to a specific NSPersistentStore lifecycle. Store changes cause the delegate
        // to tear down and attempt recovery. We should not interfere with this process.

        // During app initialization (first 15 seconds), these changes are expected
        // as SwiftData sets up CloudKit integration. Ignore them to avoid false "offline" reports.
        let timeSinceInit = Date().timeIntervalSince(initializationTime)
        if timeSinceInit < 15 {
            return
        }

        // Cancel any in-flight sync timeout task immediately.
        // The store coordinator change means CloudKit's mirroring delegate is
        // tearing down and rebuilding — any pending sync timeout is now stale
        // and would produce CancellationError log noise if left running.
        syncingTask?.cancel()
        syncingTask = nil
        if isSyncing {
            isSyncing = false
            pendingSyncCount = 0
        }

        let isEnabled = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.enableCloudKitSync
        ) as? Bool ?? true
        let isActive = UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)

        guard isEnabled && isActive else { return }

        // Schedule a delayed health check to see if CloudKit reconnects
        // If it doesn't reconnect within 5 seconds, update health status.
        // This gives the mirroring delegate time to complete its teardown/rebuild cycle.
        Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
            } catch is CancellationError {
                return  // Task was cancelled — another store change arrived
            } catch {
                return
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updateSyncHealth()
            }
        }
    }

    func handleRemoteChange() {
        // A remote change was received from CloudKit - this confirms sync is working
        SyncEventLogger.shared.log("cloudkit", status: "success", message: "Remote changes received")
        let now = Date()
        lastSuccessfulSync = now
        lastSyncError = nil
        isSyncing = false
        currentOperation = nil
        lastOperation = "Remote changes received"
        lastOperationDate = now
        pendingSyncCount = 0
        retryLogic.resetRetryCount()
        syncingTask?.cancel()
        syncingTask = nil

        // Persist
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)

        updateSyncHealth()
    }

    func handleLocalSave() {
        // Local save occurred - CloudKit will sync automatically
        pendingSyncCount += 1

        // Only start syncing indicator if not already syncing
        guard !isSyncing else { return }

        isSyncing = true
        syncStartTime = Date()
        currentOperation = "Local save queued for iCloud"
        updateSyncHealth()

        // Cancel any existing timeout task
        syncingTask?.cancel()

        // Wait for either:
        // 1. A remote change notification (confirming sync completed)
        // 2. A longer timeout (10 seconds) to account for network latency
        // The handleRemoteChange() method will cancel this task if sync completes
        syncingTask = Task { [weak self] in
            // Use longer timeout for more accurate sync status
            do {
                try await Task.sleep(for: self?.syncTimeout ?? TimeoutConstants.defaultSyncTimeout)
                guard !Task.isCancelled else { return }
            } catch is CancellationError {
                return  // Task was cancelled — sync completed or new save arrived
            } catch {
                return
            }
            await MainActor.run { [weak self] in
                guard let self, self.isSyncing else { return }

                // Check if we're online - if not, don't mark as successful
                if !self.isNetworkAvailable {
                    self.isSyncing = false
                    self.currentOperation = nil
                    self.lastOperation = "Sync paused: waiting for network"
                    self.lastOperationDate = Date()
                    self.lastSyncError = "Changes saved locally. Waiting for network to sync."
                    self.updateSyncHealth()
                    return
                }

                // Timeout reached without remote confirmation. End the spinner and keep
                // the previously known sync timestamp instead of inferring success.
                self.isSyncing = false
                self.pendingSyncCount = 0
                self.currentOperation = nil
                self.lastOperation = "Sync timed out awaiting confirmation"
                self.lastOperationDate = Date()
                self.updateSyncHealth()
            }
        }
    }

    // MARK: - CloudKit Event Handler

    /// Handles NSPersistentCloudKitContainer sync event notifications.
    /// These events provide precise success/failure information about setup, import,
    /// and export operations — more reliable than inferring sync state from
    /// NSManagedObjectContextDidSave + NSPersistentStoreRemoteChange alone.
    ///
    /// Called with pre-extracted values from the notification to avoid Sendable issues.
    func handleCloudKitEvent(
        type: NSPersistentCloudKitContainer.EventType,
        isFinished: Bool,
        succeeded: Bool,
        error: (any Error)?
    ) {
        // Events fire twice: once when started (isFinished == false) and once when finished
        guard isFinished else {
            // Event is still in progress — ensure syncing indicator is on
            if !isSyncing {
                isSyncing = true
                syncStartTime = Date()
            }
            currentOperation = "CloudKit event in progress"
            updateSyncHealth()
            return
        }

        let typeDescription: String
        switch type {
        case .setup:  typeDescription = "Setup"
        case .import: typeDescription = "Import"
        case .export: typeDescription = "Export"
        @unknown default: typeDescription = "Unknown"
        }
        currentOperation = nil

        if succeeded {
            handleSuccessfulCloudKitEvent(type: type, typeDescription: typeDescription)
        } else {
            handleFailedCloudKitEvent(type: type, typeDescription: typeDescription, error: error)
        }

        updateSyncHealth()
    }

    // MARK: - CloudKit Event Sub-handlers

    private func handleSuccessfulCloudKitEvent(
        type: NSPersistentCloudKitContainer.EventType,
        typeDescription: String
    ) {
        Self.logger.debug("CloudKit \(typeDescription) succeeded")
        SyncEventLogger.shared.log("cloudkit", status: "success", message: "\(typeDescription) completed")

        guard type != .setup else { return }

        if type == .import {
            DeduplicationCoordinator.shared.requestDeduplication()
        }

        let now = Date()
        lastSuccessfulSync = now
        lastOperation = "\(typeDescription) completed"
        lastOperationDate = now
        lastSyncError = nil
        pendingSyncCount = 0
        retryLogic.resetRetryCount()

        syncingTask?.cancel()
        syncingTask = nil
        isSyncing = false

        UserDefaults.standard.set(
            now.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate
        )
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
    }

    private func handleFailedCloudKitEvent(
        type: NSPersistentCloudKitContainer.EventType,
        typeDescription: String,
        error: (any Error)?
    ) {
        if let error {
            let nsError = error as NSError
            let domainAndCode = "\(nsError.domain) (\(nsError.code))"
            let errorDesc = nsError.localizedDescription
            Self.logger.error("CloudKit \(typeDescription) failed [\(domainAndCode)]: \(errorDesc)")
            SyncEventLogger.shared.log(
                "cloudkit",
                status: "error",
                message: "\(typeDescription) failed [\(domainAndCode)]: \(errorDesc)"
            )
            CloudKitConfigurationService.storeError(error, retryCount: retryLogic.retryAttempt)
            lastSyncError = "\(typeDescription) failed [\(domainAndCode)]: \(errorDesc)"
        } else {
            let fallbackError = "\(typeDescription) failed: Unknown error"
            Self.logger.error("\(fallbackError)")
            SyncEventLogger.shared.log("cloudkit", status: "error", message: fallbackError)
            lastSyncError = fallbackError
        }
        lastOperation = "\(typeDescription) failed"
        lastOperationDate = Date()
        isSyncing = false
        syncingTask?.cancel()
        syncingTask = nil
        UserDefaults.standard.set(lastSyncError, forKey: UserDefaultsKeys.cloudKitLastSyncError)
        if type != .setup {
            scheduleRetry()
        }
    }
}
