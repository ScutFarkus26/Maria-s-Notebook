import Foundation
import SwiftUI
import SwiftData
import CoreData

/// Service that monitors CloudKit sync activity and provides status information.
/// Since SwiftData doesn't expose per-record sync status, this service tracks
/// global sync state through Core Data notifications.
@Observable
@MainActor
final class CloudKitSyncStatusService {
    static let shared = CloudKitSyncStatusService()

    // MARK: - Observable State

    /// Whether a sync operation is currently in progress
    private(set) var isSyncing: Bool = false

    /// The last time a successful sync completed
    private(set) var lastSuccessfulSync: Date?

    /// The last sync error message, if any
    private(set) var lastSyncError: String?

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
    private let initializationTime: Date = Date()

    // MARK: - Specialized Services

    private let networkMonitor = NetworkMonitoring()
    private let retryLogic = SyncRetryLogic()
    private let healthCheck = CloudKitHealthCheck()

    // MARK: - Private State

    private var remoteChangeObserver: NSObjectProtocol?
    private var saveObserver: NSObjectProtocol?
    private var storeCoordinatorChangeObserver: NSObjectProtocol?
    private var syncStartTime: Date?
    private var modelContainer: ModelContainer?
    private var syncingTask: Task<Void, Never>?

    // Task tracking for notification handlers to prevent accumulation
    private var pendingRemoteChangeTask: Task<Void, Never>?
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingStoreChangeTask: Task<Void, Never>?

    /// Pending sync count - tracks how many saves are waiting for CloudKit confirmation
    private var pendingSyncCount: Int = 0

    /// Maximum time to wait for sync confirmation before assuming success (in nanoseconds)
    private let syncTimeoutNanoseconds: UInt64 = TimeoutConstants.defaultSyncTimeout

    // MARK: - Initialization

    init() {
        // Load persisted state
        if let timestamp = UserDefaults.standard.object(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate) as? TimeInterval {
            lastSuccessfulSync = Date(timeIntervalSince1970: timestamp)
        }
        lastSyncError = UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudKitLastSyncError)

        // Setup network monitoring callbacks
        networkMonitor.setNetworkChangeHandler { [weak self] isAvailable in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.handleNetworkChange(isAvailable: isAvailable)
            }
        }

        // Setup iCloud account monitoring callbacks
        healthCheck.setICloudChangeHandler { [weak self] isAvailable in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
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
        self.modelContainer = container
        
        // Delay starting observers to allow CloudKit initialization to complete
        // SwiftData creates temporary stores during CloudKit setup that get torn down
        // We don't want to report these expected teardowns as errors
        Task { [weak self] in
            // Wait 2 seconds for initial CloudKit setup to complete
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.startObserving()
                self.healthCheck.startICloudAccountMonitoring()
                self.updateSyncHealth()
            }
        }
    }

    // MARK: - Observation

    private func startObserving() {
        // Observe remote changes (incoming CloudKit sync)
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingRemoteChangeTask?.cancel()
                self.pendingRemoteChangeTask = Task { @MainActor [weak self] in
                    self?.handleRemoteChange()
                }
            }
        }

        // Observe local saves (outgoing sync trigger)
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingSaveTask?.cancel()
                self.pendingSaveTask = Task { @MainActor [weak self] in
                    self?.handleLocalSave()
                }
            }
        }

        // Observe store coordinator changes (CloudKit delegate teardowns)
        // This notification fires when stores are added/removed from the coordinator
        // which can happen during migrations or configuration changes
        storeCoordinatorChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreCoordinatorStoresDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingStoreChangeTask?.cancel()
                self.pendingStoreChangeTask = Task { @MainActor [weak self] in
                    self?.handleStoreCoordinatorChange()
                }
            }
        }
    }

    private nonisolated func stopObserving() {
        Task { @MainActor [weak self] in
            // Cancel all pending tasks
            self?.pendingRemoteChangeTask?.cancel()
            self?.pendingRemoteChangeTask = nil
            self?.pendingSaveTask?.cancel()
            self?.pendingSaveTask = nil
            self?.pendingStoreChangeTask?.cancel()
            self?.pendingStoreChangeTask = nil

            if let observer = self?.remoteChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = self?.saveObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = self?.storeCoordinatorChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self?.remoteChangeObserver = nil
            self?.saveObserver = nil
            self?.storeCoordinatorChangeObserver = nil
        }
    }

    // MARK: - Network & iCloud Change Handlers

    private func handleNetworkChange(isAvailable: Bool) {
        if isAvailable {
            // Network restored - clear network-related errors and trigger retry
            if let error = lastSyncError, error.contains("network") || error.contains("offline") || error.contains("Waiting") {
                lastSyncError = nil
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
            }
            // Trigger retry for any pending syncs
            retryPendingSync()
        }
        updateSyncHealth()
    }

    private func handleICloudAccountChange(isAvailable: Bool) {
        if isAvailable {
            // User signed into iCloud - clear any offline errors and retry
            if lastSyncError?.contains("iCloud") == true || lastSyncError?.contains("signed in") == true || lastSyncError?.contains("Sign into") == true {
                lastSyncError = nil
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
            }
            // Trigger retry for any pending syncs
            retryPendingSync()
        } else {
            // User signed out of iCloud
            lastSyncError = "iCloud account signed out. Sign in to resume syncing."
            UserDefaults.standard.set(lastSyncError, forKey: UserDefaultsKeys.cloudKitLastSyncError)
            // Cancel any pending retries
            retryLogic.cancelRetry()
        }
        updateSyncHealth()
    }

    // MARK: - Event Handlers

    private func handleStoreCoordinatorChange() {
        // The persistent store coordinator's stores changed
        // This can happen during:
        // 1. Initial CloudKit setup (expected - SwiftData creates temp stores)
        // 2. Migrations or configuration changes
        // 3. CloudKit delegate teardown/rebuild
        
        // During app initialization (first 15 seconds), these changes are expected
        // as SwiftData sets up CloudKit integration. Ignore them to avoid false "offline" reports.
        let timeSinceInit = Date().timeIntervalSince(initializationTime)
        if timeSinceInit < 15 {
            // Still in startup phase - these teardowns are expected
            return
        }
        
        let isEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
        let isActive = UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)
        
        guard isEnabled && isActive else { return }
        
        // Schedule a delayed health check to see if CloudKit reconnects
        // If it doesn't reconnect within 3 seconds, we'll update the health status
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                // Only update if we're still showing as active but haven't had recent sync
                if let lastSync = self.lastSuccessfulSync {
                    let elapsed = Date().timeIntervalSince(lastSync)
                    if elapsed > 10 { // More than 10 seconds since last sync
                        // Try to trigger a sync to reconnect
                        Task {
                            _ = await self.syncNow()
                        }
                    }
                }
                self.updateSyncHealth()
            }
        }
    }

    private func handleRemoteChange() {
        // A remote change was received from CloudKit - this confirms sync is working
        lastSuccessfulSync = Date()
        lastSyncError = nil
        isSyncing = false
        pendingSyncCount = 0
        retryLogic.resetRetryCount()
        syncingTask?.cancel()
        syncingTask = nil

        // Persist
        UserDefaults.standard.set(lastSuccessfulSync!.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)

        updateSyncHealth()
    }

    private func handleLocalSave() {
        // Local save occurred - CloudKit will sync automatically
        pendingSyncCount += 1

        // Only start syncing indicator if not already syncing
        guard !isSyncing else { return }

        isSyncing = true
        syncStartTime = Date()
        updateSyncHealth()

        // Cancel any existing timeout task
        syncingTask?.cancel()

        // Wait for either:
        // 1. A remote change notification (confirming sync completed)
        // 2. A longer timeout (10 seconds) to account for network latency
        // The handleRemoteChange() method will cancel this task if sync completes
        syncingTask = Task { [weak self] in
            // Use longer timeout for more accurate sync status
            try? await Task.sleep(nanoseconds: self?.syncTimeoutNanoseconds ?? TimeoutConstants.defaultSyncTimeout)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self = self, self.isSyncing else { return }

                // Check if we're online - if not, don't mark as successful
                if !self.isNetworkAvailable {
                    self.isSyncing = false
                    self.lastSyncError = "Changes saved locally. Waiting for network to sync."
                    self.updateSyncHealth()
                    return
                }

                if !self.isICloudAvailable {
                    self.isSyncing = false
                    self.lastSyncError = "Changes saved locally. Sign into iCloud to sync."
                    self.updateSyncHealth()
                    return
                }

                // Timeout reached without remote confirmation, but no error
                // Mark as successful since SwiftData doesn't always fire remote change notifications
                // for outgoing-only syncs
                self.isSyncing = false
                self.pendingSyncCount = 0
                self.lastSuccessfulSync = Date()
                UserDefaults.standard.set(self.lastSuccessfulSync!.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
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

        do {
            let context = ModelContext(container)
            try context.save()

            // Update success state
            lastSuccessfulSync = Date()
            lastSyncError = nil
            UserDefaults.standard.set(lastSuccessfulSync!.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)

            // Keep syncing indicator briefly to show activity
            try? await Task.sleep(nanoseconds: 500_000_000)
            isSyncing = false
            updateSyncHealth()
            return true
        } catch {
            lastSyncError = error.localizedDescription
            UserDefaults.standard.set(lastSyncError, forKey: UserDefaultsKeys.cloudKitLastSyncError)
            isSyncing = false
            updateSyncHealth()
            return false
        }
    }

    // MARK: - Health Assessment

    private func updateSyncHealth() {
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
    private func scheduleRetry() {
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
