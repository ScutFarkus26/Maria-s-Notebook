import Foundation
import SwiftUI
import SwiftData
import CoreData
import Combine

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

    // MARK: - Types

    enum SyncHealth: Equatable {
        case healthy          // Recent successful sync, no errors
        case syncing          // Currently syncing
        case warning          // Minor issues (e.g., slow sync)
        case error(String)    // Sync error occurred
        case offline          // No network or iCloud unavailable
        case unknown          // Status unknown (startup)

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
    private var syncStartTime: Date?
    private var modelContainer: ModelContainer?
    private var syncingTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        // Load persisted state
        if let timestamp = UserDefaults.standard.object(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate) as? TimeInterval {
            lastSuccessfulSync = Date(timeIntervalSince1970: timestamp)
        }
        lastSyncError = UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudKitLastSyncError)

        // Determine initial health
        updateSyncHealth()
    }

    deinit {
        stopObserving()
    }

    // MARK: - Setup

    func configure(with container: ModelContainer) {
        self.modelContainer = container
        startObserving()
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
                self?.handleRemoteChange()
            }
        }

        // Observe local saves (outgoing sync trigger)
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLocalSave()
            }
        }
    }

    private nonisolated func stopObserving() {
        Task { @MainActor [weak self] in
            if let observer = self?.remoteChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = self?.saveObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self?.remoteChangeObserver = nil
            self?.saveObserver = nil
        }
    }

    // MARK: - Event Handlers

    private func handleRemoteChange() {
        // A remote change was received from CloudKit
        lastSuccessfulSync = Date()
        lastSyncError = nil
        isSyncing = false
        syncingTask?.cancel()
        syncingTask = nil

        // Persist
        UserDefaults.standard.set(lastSuccessfulSync!.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)

        updateSyncHealth()
    }

    private func handleLocalSave() {
        // Local save occurred - CloudKit will sync automatically
        // Mark as syncing briefly
        guard !isSyncing else { return }

        isSyncing = true
        syncStartTime = Date()
        updateSyncHealth()

        // Cancel any existing timeout task
        syncingTask?.cancel()

        // Auto-clear syncing state after a short delay
        // (CloudKit sync happens asynchronously)
        syncingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self = self, self.isSyncing else { return }
                self.isSyncing = false
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
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
        updateSyncHealth()
    }
}
