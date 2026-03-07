import Foundation
import SwiftUI

/// Service responsible for monitoring CloudKit health and availability
@Observable
@MainActor
final class CloudKitHealthCheck {
    // MARK: - Observable State
    
    /// Overall sync health status
    private(set) var syncHealth: SyncHealth = .unknown
    
    /// Whether iCloud account is available
    private(set) var isICloudAvailable: Bool = true
    
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
    
    private var iCloudAccountObserver: NSObjectProtocol?
    private var pendingICloudTask: Task<Void, Never>?
    private var iCloudChangeContinuation: AsyncStream<Bool>.Continuation?
    
    // MARK: - Initialization
    
    init() {
        // Check initial iCloud availability
        isICloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        
        // Set initial health based on iCloud availability
        let isEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
        let isActive = UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)
        
        if isEnabled && isActive && isICloudAvailable {
            // Load persisted state to determine initial health
            let syncDateKey = UserDefaultsKeys.cloudKitLastSuccessfulSyncDate
            if let lastSyncTimestamp = UserDefaults.standard.object(forKey: syncDateKey) as? TimeInterval {
                let lastSync = Date(timeIntervalSince1970: lastSyncTimestamp)
                let elapsed = Date().timeIntervalSince(lastSync)
                let lastError = UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudKitLastSyncError)
                
                if elapsed < 3600 && lastError == nil { // Within 1 hour and no errors
                    syncHealth = .healthy
                } else {
                    syncHealth = .unknown
                }
            } else {
                syncHealth = .unknown
            }
        } else {
            syncHealth = .offline
        }
    }
    
    deinit {
        stopObserving()
    }
    
    // MARK: - Public API
    
    /// Observe iCloud account status changes as an AsyncStream
    func observeICloudChanges() -> AsyncStream<Bool> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            iCloudChangeContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    self?.iCloudChangeContinuation = nil
                }
            }
        }
    }
    
    /// Start monitoring iCloud account changes
    func startICloudAccountMonitoring() {
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
    
    // swiftlint:disable function_parameter_count
    /// Update the sync health status
    /// - Parameters:
    ///   - isSyncing: Whether a sync is currently in progress
    ///   - lastSuccessfulSync: The last successful sync timestamp
    ///   - lastSyncError: The last sync error message
    ///   - isNetworkAvailable: Whether network is available
    ///   - isEnabled: Whether CloudKit sync is enabled
    ///   - isActive: Whether CloudKit is active
    func updateSyncHealth(
        isSyncing: Bool,
        lastSuccessfulSync: Date?,
        lastSyncError: String?,
        isNetworkAvailable: Bool,
        isEnabled: Bool,
        isActive: Bool
    ) {
        guard isEnabled, isActive, isNetworkAvailable, isICloudAvailable else {
            syncHealth = .offline
            return
        }
        if isSyncing { syncHealth = .syncing; return }

        if let health = syncHealthFromError(lastSyncError, lastSuccessfulSync: lastSuccessfulSync) {
            syncHealth = health
            return
        }

        syncHealth = syncHealthFromRecency(lastSuccessfulSync)
    }
    // swiftlint:enable function_parameter_count

    private func syncHealthFromError(
        _ lastSyncError: String?, lastSuccessfulSync: Date?
    ) -> SyncHealth? {
        guard let error = lastSyncError, !error.isEmpty else { return nil }
        if let lastSync = lastSuccessfulSync, Date().timeIntervalSince(lastSync) < 30 {
            return .healthy // Within 30 seconds — likely transient
        }
        return .error(error)
    }

    private func syncHealthFromRecency(_ lastSuccessfulSync: Date?) -> SyncHealth {
        guard let lastSync = lastSuccessfulSync else { return .unknown }
        let elapsed = Date().timeIntervalSince(lastSync)
        if elapsed < 3600 { return .healthy }
        return .warning
    }
    
    // MARK: - Private Methods
    
    private func handleICloudAccountChange() {
        let wasAvailable = isICloudAvailable
        isICloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        
        if wasAvailable != isICloudAvailable {
            iCloudChangeContinuation?.yield(isICloudAvailable)
        }
    }
    
    private nonisolated func stopObserving() {
        Task { @MainActor [weak self] in
            self?.pendingICloudTask?.cancel()
            self?.pendingICloudTask = nil
            
            if let observer = self?.iCloudAccountObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self?.iCloudAccountObserver = nil
        }
    }
}
