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
    private static let logger = Logger.sync
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
    private var cloudKitEventObserver: NSObjectProtocol?
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
    private let syncTimeout: Duration = TimeoutConstants.defaultSyncTimeout

    // MARK: - Initialization

    init() {
        // Load persisted state
        if let timestamp = UserDefaults.standard.object(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate) as? TimeInterval {
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

        // Observe CloudKit sync events (setup, import, export) for precise status tracking.
        // This is Apple's recommended notification (iOS 14+/macOS 11+) for monitoring
        // NSPersistentCloudKitContainer sync operations. It provides the exact event type
        // and whether it succeeded or failed, which is more precise than inferring sync
        // state from NSManagedObjectContextDidSave + NSPersistentStoreRemoteChange alone.
        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract event data before crossing isolation boundary (Notification is not Sendable)
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let type = event.type
            let isFinished = event.endDate != nil
            let succeeded = event.succeeded
            let errorDesc = event.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleCloudKitEvent(type: type, isFinished: isFinished, succeeded: succeeded, errorDescription: errorDesc)
            }
        }
    }

    /// Removes all notification observers and cancels pending tasks.
    /// Safe to call multiple times. Must be called on @MainActor.
    private func removeAllObservers() {
        // Cancel all pending tasks
        pendingRemoteChangeTask?.cancel()
        pendingRemoteChangeTask = nil
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        pendingStoreChangeTask?.cancel()
        pendingStoreChangeTask = nil

        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = saveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = storeCoordinatorChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = cloudKitEventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        remoteChangeObserver = nil
        saveObserver = nil
        storeCoordinatorChangeObserver = nil
        cloudKitEventObserver = nil
    }

    private nonisolated func stopObserving() {
        Task { @MainActor [weak self] in
            self?.removeAllObservers()
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

        let isEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
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
                guard let self = self else { return }
                self.updateSyncHealth()
            }
        }
    }

    private func handleRemoteChange() {
        // A remote change was received from CloudKit - this confirms sync is working
        let now = Date()
        lastSuccessfulSync = now
        lastSyncError = nil
        isSyncing = false
        pendingSyncCount = 0
        retryLogic.resetRetryCount()
        syncingTask?.cancel()
        syncingTask = nil

        // Persist
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
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
            do {
                try await Task.sleep(for: self?.syncTimeout ?? TimeoutConstants.defaultSyncTimeout)
                guard !Task.isCancelled else { return }
            } catch is CancellationError {
                return  // Task was cancelled — sync completed or new save arrived
            } catch {
                return
            }
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
                let now = Date()
                self.lastSuccessfulSync = now
                UserDefaults.standard.set(now.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
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
    private func handleCloudKitEvent(
        type: NSPersistentCloudKitContainer.EventType,
        isFinished: Bool,
        succeeded: Bool,
        errorDescription: String?
    ) {
        // Events fire twice: once when started (isFinished == false) and once when finished
        guard isFinished else {
            // Event is still in progress — ensure syncing indicator is on
            if !isSyncing {
                isSyncing = true
                syncStartTime = Date()
                updateSyncHealth()
            }
            return
        }

        let typeDescription: String
        switch type {
        case .setup:  typeDescription = "Setup"
        case .import: typeDescription = "Import"
        case .export: typeDescription = "Export"
        @unknown default: typeDescription = "Unknown"
        }

        if succeeded {
            Self.logger.debug("CloudKit \(typeDescription) succeeded")

            // Update lastSuccessfulSync for data operations (import/export), not setup
            if type != .setup {
                let now = Date()
                lastSuccessfulSync = now
                lastSyncError = nil
                pendingSyncCount = 0
                retryLogic.resetRetryCount()

                // Cancel the inference-based sync timeout since we have a definitive result
                syncingTask?.cancel()
                syncingTask = nil
                isSyncing = false

                UserDefaults.standard.set(now.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
            }
        } else if let errorDesc = errorDescription {
            Self.logger.error("CloudKit \(typeDescription) failed: \(errorDesc)")

            lastSyncError = "\(typeDescription) failed: \(errorDesc)"
            isSyncing = false
            syncingTask?.cancel()
            syncingTask = nil

            UserDefaults.standard.set(lastSyncError, forKey: UserDefaultsKeys.cloudKitLastSyncError)

            // Schedule retry for data operation failures (not setup)
            if type != .setup {
                scheduleRetry()
            }
        }

        updateSyncHealth()
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
            let now = Date()
            lastSuccessfulSync = now
            lastSyncError = nil
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
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
