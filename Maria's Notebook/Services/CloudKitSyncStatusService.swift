import Foundation
import SwiftUI
import SwiftData
import CoreData
import OSLog

/// Service that monitors CloudKit sync activity and provides status information.
/// Since SwiftData doesn't expose per-record sync status, this service tracks
/// global sync state through Core Data notifications.
@Observable
@MainActor
final class CloudKitSyncStatusService {
    static let logger = Logger.sync
    static let shared = CloudKitSyncStatusService()

    // MARK: - Observable State

    /// Whether a sync operation is currently in progress
    var isSyncing: Bool = false

    /// The last time a successful sync completed
    var lastSuccessfulSync: Date?

    /// The last sync error message, if any
    var lastSyncError: String?

    /// Overall sync health status (delegated to CloudKitHealthCheck)
    var syncHealth: CloudKitHealthCheck.SyncHealth {
        healthCheck.syncHealth
    }

    /// Whether network is available (delegated to NetworkMonitoring)
    var isNetworkAvailable: Bool {
        networkMonitor.isNetworkAvailable
    }

    /// Whether iCloud account is available (delegated to CloudKitHealthCheck)
    var isICloudAvailable: Bool {
        healthCheck.isICloudAvailable
    }

    /// Timestamp when the service was initialized (used for startup grace period)
    let initializationTime: Date = Date()

    // MARK: - Specialized Services

    let networkMonitor = NetworkMonitoring()
    let retryLogic = SyncRetryLogic()
    let healthCheck = CloudKitHealthCheck()

    // MARK: - Internal State (accessed by extensions)

    var remoteChangeObserver: NSObjectProtocol?
    var saveObserver: NSObjectProtocol?
    var storeCoordinatorChangeObserver: NSObjectProtocol?
    var cloudKitEventObserver: NSObjectProtocol?
    var syncStartTime: Date?
    private var modelContainer: ModelContainer?
    var syncingTask: Task<Void, Never>?

    // Task tracking for notification handlers to prevent accumulation
    var pendingRemoteChangeTask: Task<Void, Never>?
    var pendingSaveTask: Task<Void, Never>?
    var pendingStoreChangeTask: Task<Void, Never>?

    /// Pending sync count - tracks how many saves are waiting for CloudKit confirmation
    var pendingSyncCount: Int = 0

    /// Maximum time to wait for sync confirmation before assuming success (in nanoseconds)
    let syncTimeout: Duration = TimeoutConstants.defaultSyncTimeout

    // MARK: - Initialization

    init() {
        // Load persisted state
        let syncDateKey = UserDefaultsKeys.cloudKitLastSuccessfulSyncDate
        if let timestamp = UserDefaults.standard.object(forKey: syncDateKey) as? TimeInterval {
            lastSuccessfulSync = Date(timeIntervalSince1970: timestamp)
        }
        lastSyncError = UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudKitLastSyncError)

        // Setup network monitoring using AsyncStream
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for await isAvailable in self.networkMonitor.observeNetworkChanges() {
                self.handleNetworkChange(isAvailable: isAvailable)
            }
        }

        // Setup iCloud account monitoring using AsyncStream
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for await isAvailable in self.healthCheck.observeICloudChanges() {
                self.handleICloudAccountChange(isAvailable: isAvailable)
            }
        }

        // Update health status after initialization
        updateSyncHealth()
    }

    deinit {
        stopObserving()
        // Note: Cannot call stopNetworkMonitoring() from deinit since it's MainActor-isolated
        // The specialized services will be cleaned up when deallocated
    }

    // MARK: - Setup

    func configure(with container: ModelContainer) {
        // Tear down any existing observers before reconfiguring to prevent
        // duplicate observers and stale references (Apple best practice:
        // NSCloudKitMirroringDelegate instances are not reusable)
        removeAllObservers()
        syncingTask?.cancel()
        syncingTask = nil

        self.modelContainer = container

        // Delay starting observers to allow CloudKit initialization to complete
        // SwiftData creates temporary stores during CloudKit setup that get torn down
        // We don't want to report these expected teardowns as errors
        Task { [weak self] in
            // Wait 2 seconds for initial CloudKit setup to complete
            do {
                try await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
            } catch is CancellationError {
                return  // Task was cancelled — expected during reconfiguration
            } catch {
                return
            }
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.startObserving()
                self.healthCheck.startICloudAccountMonitoring()
                self.updateSyncHealth()
            }
        }
    }

    // MARK: - Manual Sync

    /// Triggers a save on the model context to push pending changes.
    /// Returns true if save succeeded, false otherwise.
    @discardableResult
    func syncNow() async -> Bool {
        guard let container = modelContainer else { return false }

        isSyncing = true
        syncStartTime = Date()
        updateSyncHealth()
        SyncEventLogger.shared.log("cloudkit", status: "started", message: "Manual sync initiated")

        do {
            let context = ModelContext(container)
            try context.save()

            // Update success state
            let now = Date()
            lastSuccessfulSync = now
            lastSyncError = nil
            SyncEventLogger.shared.log("cloudkit", status: "success", message: "Sync completed successfully")
            UserDefaults.standard.set(
                now.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate
            )
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)

            // Keep syncing indicator briefly to show activity
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                // CancellationError or other — just proceed
            }
            isSyncing = false
            updateSyncHealth()
            return true
        } catch {
            lastSyncError = error.localizedDescription
            UserDefaults.standard.set(lastSyncError, forKey: UserDefaultsKeys.cloudKitLastSyncError)
            SyncEventLogger.shared.log("cloudkit", status: "error", message: error.localizedDescription)
            isSyncing = false
            updateSyncHealth()
            return false
        }
    }

    // MARK: - Health Assessment

    func updateSyncHealth() {
        let isEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
        let isActive = UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)

        healthCheck.updateSyncHealth(
            isSyncing: isSyncing,
            lastSuccessfulSync: lastSuccessfulSync,
            lastSyncError: lastSyncError,
            isNetworkAvailable: isNetworkAvailable,
            isEnabled: isEnabled,
            isActive: isActive
        )
    }

    /// Clear any stored error state
    func clearError() {
        lastSyncError = nil
        retryLogic.resetRetryCount()
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
        updateSyncHealth()
    }

    // MARK: - Retry Logic

    /// Schedules a retry with exponential backoff (delegated to SyncRetryLogic)
    func scheduleRetry() {
        retryLogic.scheduleRetry(
            canRetry: { [weak self] in
                guard let self = self else { return false }
                return self.isNetworkAvailable && self.isICloudAvailable
            },
            syncAction: { [weak self] in
                guard let self = self else { return false }
                return await self.syncNow()
            },
            onMaxRetriesReached: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.lastSyncError = "Sync failed after 5 attempts. Please try again later."
                    UserDefaults.standard.set(self.lastSyncError, forKey: UserDefaultsKeys.cloudKitLastSyncError)
                    SyncEventLogger.shared.log(
                        "cloudkit", status: "error",
                        message: "Sync failed after 5 retry attempts"
                    )
                    self.updateSyncHealth()
                }
            }
        )
    }

    /// Called when network is restored to trigger pending retries
    func retryPendingSync() {
        retryLogic.retryPendingSync(
            canRetry: { [weak self] in
                guard let self = self else { return false }
                return self.isNetworkAvailable && self.isICloudAvailable
            },
            hasPendingWork: { [weak self] in
                guard let self = self else { return false }
                return self.lastSyncError != nil || self.pendingSyncCount > 0
            },
            syncAction: { [weak self] in
                _ = await self?.syncNow()
            }
        )
    }
}
