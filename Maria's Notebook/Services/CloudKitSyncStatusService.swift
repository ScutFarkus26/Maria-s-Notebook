import Foundation
import SwiftUI
import SwiftData
import CoreData
import Combine
import Network

/// Service that monitors CloudKit sync activity and provides status information.
/// Since SwiftData doesn't expose per-record sync status, this service tracks
/// global sync state through Core Data notifications.
@MainActor
final class CloudKitSyncStatusService: ObservableObject {
    static let shared = CloudKitSyncStatusService()

    // MARK: - Published State

    /// Whether a sync operation is currently in progress
    @Published private(set) var isSyncing: Bool = false

    /// The last time a successful sync completed
    @Published private(set) var lastSuccessfulSync: Date?

    /// The last sync error message, if any
    @Published private(set) var lastSyncError: String?

    /// Overall sync health status
    @Published private(set) var syncHealth: SyncHealth = .unknown

    /// Whether network is available
    @Published private(set) var isNetworkAvailable: Bool = true

    /// Whether iCloud account is available
    @Published private(set) var isICloudAvailable: Bool = true

    // MARK: - Types

    enum SyncHealth: Equatable, Sendable {
        case healthy          // Recent successful sync, no errors
        case syncing          // Currently syncing
        case warning          // Minor issues (e.g., slow sync)
        case error(String)    // Sync error occurred
        case offline          // No network or iCloud unavailable
        case unknown          // Status unknown (startup)

        nonisolated static func == (lhs: SyncHealth, rhs: SyncHealth) -> Bool {
            switch (lhs, rhs) {
            case (.healthy, .healthy): return true
            case (.syncing, .syncing): return true
            case (.warning, .warning): return true
            case (.error(let l), .error(let r)): return l == r
            case (.offline, .offline): return true
            case (.unknown, .unknown): return true
            default: return false
            }
        }

        var color: Color {
            switch self {
            case .healthy: return .green
            case .syncing: return .blue
            case .warning: return .orange
            case .error: return .red
            case .offline: return .gray
            case .unknown: return .gray
            }
        }

        var icon: String {
            switch self {
            case .healthy: return "checkmark.icloud"
            case .syncing: return "arrow.triangle.2.circlepath.icloud"
            case .warning: return "exclamationmark.icloud"
            case .error: return "xmark.icloud"
            case .offline: return "icloud.slash"
            case .unknown: return "icloud"
            }
        }

        var displayText: String {
            switch self {
            case .healthy: return "Synced"
            case .syncing: return "Syncing..."
            case .warning: return "Sync Delayed"
            case .error: return "Sync Error"
            case .offline: return "Offline"
            case .unknown: return "Checking..."
            }
        }
    }

    // MARK: - Private State

    private var remoteChangeObserver: NSObjectProtocol?
    private var saveObserver: NSObjectProtocol?
    private var iCloudAccountObserver: NSObjectProtocol?
    private var syncStartTime: Date?
    private var modelContainer: ModelContainer?
    private var syncingTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?
    private let networkQueue = DispatchQueue(label: "com.mariasnotebook.networkmonitor")

    // Task tracking for notification handlers to prevent accumulation
    private var pendingRemoteChangeTask: Task<Void, Never>?
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingICloudTask: Task<Void, Never>?
    private var pendingNetworkTask: Task<Void, Never>?

    /// Pending sync count - tracks how many saves are waiting for CloudKit confirmation
    private var pendingSyncCount: Int = 0

    /// Maximum time to wait for sync confirmation before assuming success (in nanoseconds)
    private let syncTimeoutNanoseconds: UInt64 = 10_000_000_000 // 10 seconds

    // MARK: - Retry Logic

    /// Current retry attempt count for failed syncs
    private var retryAttempt: Int = 0

    /// Maximum number of retry attempts before giving up
    private let maxRetryAttempts: Int = 5

    /// Base delay for exponential backoff (in seconds)
    private let baseRetryDelay: Double = 2.0

    /// Task for retry operations
    private var retryTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        // Load persisted state
        if let timestamp = UserDefaults.standard.object(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate) as? TimeInterval {
            lastSuccessfulSync = Date(timeIntervalSince1970: timestamp)
        }
        lastSyncError = UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudKitLastSyncError)

        // Check initial iCloud availability
        isICloudAvailable = FileManager.default.ubiquityIdentityToken != nil

        // Start network monitoring
        startNetworkMonitoring()

        // Determine initial health
        updateSyncHealth()
    }

    deinit {
        stopObserving()
        // Note: Cannot call stopNetworkMonitoring() from deinit since it's MainActor-isolated
        // The NWPathMonitor will be cleaned up when the object is deallocated
    }

    // MARK: - Setup

    func configure(with container: ModelContainer) {
        self.modelContainer = container
        startObserving()
        startICloudAccountMonitoring()
        updateSyncHealth()
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
    }

    private nonisolated func stopObserving() {
        Task { @MainActor [weak self] in
            // Cancel all pending tasks
            self?.pendingRemoteChangeTask?.cancel()
            self?.pendingRemoteChangeTask = nil
            self?.pendingSaveTask?.cancel()
            self?.pendingSaveTask = nil
            self?.pendingICloudTask?.cancel()
            self?.pendingICloudTask = nil
            self?.pendingNetworkTask?.cancel()
            self?.pendingNetworkTask = nil

            if let observer = self?.remoteChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = self?.saveObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = self?.iCloudAccountObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self?.remoteChangeObserver = nil
            self?.saveObserver = nil
            self?.iCloudAccountObserver = nil
        }
    }

    // MARK: - iCloud Account Monitoring

    private func startICloudAccountMonitoring() {
        // Observe iCloud account changes (sign-in/sign-out)
        iCloudAccountObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingICloudTask?.cancel()
                self.pendingICloudTask = Task { @MainActor [weak self] in
                    self?.handleICloudAccountChange()
                }
            }
        }
    }

    private func handleICloudAccountChange() {
        let wasAvailable = isICloudAvailable
        isICloudAvailable = FileManager.default.ubiquityIdentityToken != nil

        if wasAvailable != isICloudAvailable {
            if isICloudAvailable {
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
                retryTask?.cancel()
                retryTask = nil
            }
            updateSyncHealth()
        }
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingNetworkTask?.cancel()
                self.pendingNetworkTask = Task { @MainActor [weak self] in
                    self?.handleNetworkChange(path)
                }
            }
        }
        networkMonitor?.start(queue: networkQueue)
    }

    private func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    private func handleNetworkChange(_ path: NWPath) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = path.status == .satisfied

        if wasAvailable != isNetworkAvailable {
            if isNetworkAvailable {
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
    }

    // MARK: - Event Handlers

    private func handleRemoteChange() {
        // A remote change was received from CloudKit - this confirms sync is working
        lastSuccessfulSync = Date()
        lastSyncError = nil
        isSyncing = false
        pendingSyncCount = 0
        retryAttempt = 0 // Reset retry count on success
        syncingTask?.cancel()
        syncingTask = nil
        retryTask?.cancel()
        retryTask = nil

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
            try? await Task.sleep(nanoseconds: self?.syncTimeoutNanoseconds ?? 10_000_000_000)
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
        // Check if CloudKit is enabled and active
        let isEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
        let isActive = UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)

        guard isEnabled else {
            syncHealth = .offline
            return
        }

        guard isActive else {
            syncHealth = .offline
            return
        }

        // Check network availability
        guard isNetworkAvailable else {
            syncHealth = .offline
            return
        }

        // Check iCloud availability
        guard isICloudAvailable else {
            syncHealth = .offline
            return
        }

        // Check current state
        if isSyncing {
            syncHealth = .syncing
            return
        }

        // Check for errors
        if let error = lastSyncError, !error.isEmpty {
            syncHealth = .error(error)
            return
        }

        // Check recency of last sync
        if let lastSync = lastSuccessfulSync {
            let elapsed = Date().timeIntervalSince(lastSync)
            if elapsed < 300 { // Within 5 minutes
                syncHealth = .healthy
            } else if elapsed < 3600 { // Within 1 hour
                syncHealth = .healthy // Still healthy, just not recent
            } else {
                syncHealth = .warning // More than an hour since last sync
            }
        } else {
            syncHealth = .unknown
        }
    }

    /// Clear any stored error state
    func clearError() {
        lastSyncError = nil
        retryAttempt = 0
        retryTask?.cancel()
        retryTask = nil
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
        updateSyncHealth()
    }

    // MARK: - Retry Logic

    /// Schedules a retry with exponential backoff
    private func scheduleRetry() {
        guard retryAttempt < maxRetryAttempts else {
            lastSyncError = "Sync failed after \(maxRetryAttempts) attempts. Please try again later."
            UserDefaults.standard.set(lastSyncError, forKey: UserDefaultsKeys.cloudKitLastSyncError)
            updateSyncHealth()
            return
        }

        retryTask?.cancel()

        // Calculate delay with exponential backoff: 2s, 4s, 8s, 16s, 32s
        let delay = baseRetryDelay * pow(2.0, Double(retryAttempt))
        retryAttempt += 1

        retryTask = Task { [weak self] in
            guard let self = self else { return }

            // Wait for the backoff delay
            let delayNanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }

            // Check if conditions are now favorable
            guard self.isNetworkAvailable && self.isICloudAvailable else {
                // Still offline, schedule another retry
                self.scheduleRetry()
                return
            }

            // Attempt sync
            let success = await self.syncNow()
            if !success && self.retryAttempt < self.maxRetryAttempts {
                self.scheduleRetry()
            }
        }
    }

    /// Called when network is restored to trigger pending retries
    func retryPendingSync() {
        guard isNetworkAvailable && isICloudAvailable else { return }
        guard lastSyncError != nil || pendingSyncCount > 0 else { return }

        // Reset retry count and try immediately
        retryAttempt = 0
        Task {
            await syncNow()
        }
    }
}
