import CloudKit
import Foundation
import OSLog
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
        // Initial iCloud hint from the ubiquity identity token (synchronous but
        // reflects iCloud *Drive*, which users can disable while CloudKit still
        // works). The authoritative CKContainer.accountStatus check replaces it
        // asynchronously in startICloudAccountMonitoring / refreshAccountStatus.
        isICloudAvailable = FileManager.default.ubiquityIdentityToken != nil

        // Set initial health based on persisted sync state and active configuration.
        let isEnabled = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.enableCloudKitSync
        ) as? Bool ?? true
        let isActive = UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)

        if isEnabled && isActive {
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
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.iCloudChangeContinuation = nil
                }
            }
        }
    }
    
    /// Start monitoring iCloud account changes.
    ///
    /// Uses `CKAccountChanged` + `CKContainer.accountStatus`, the CloudKit
    /// APIs for account availability. The previously used
    /// `ubiquityIdentityToken` reports iCloud *Drive* identity — it is nil
    /// whenever the user turns iCloud Drive off, even though CloudKit sync
    /// keeps working, which produced false "iCloud unavailable" states.
    func startICloudAccountMonitoring() {
        iCloudAccountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingICloudTask?.cancel()
                self.pendingICloudTask = Task { @MainActor [weak self] in
                    await self?.handleICloudAccountChange()
                }
            }
        }

        // Replace the synchronous init-time hint with the authoritative status.
        pendingICloudTask?.cancel()
        pendingICloudTask = Task { @MainActor [weak self] in
            await self?.handleICloudAccountChange()
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
        guard isEnabled, isActive, isNetworkAvailable else {
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
    
    private func handleICloudAccountChange() async {
        guard let status = await Self.fetchAccountStatus() else { return }
        let wasAvailable = isICloudAvailable
        isICloudAvailable = status == .available

        if wasAvailable != isICloudAvailable {
            iCloudChangeContinuation?.yield(isICloudAvailable)
        }
    }

    /// Queries CloudKit for the account status of the app's container.
    /// Returns nil on error (status unknown — keep the current value rather
    /// than flapping the UI on a transient failure).
    private static func fetchAccountStatus() async -> CKAccountStatus? {
        let ckContainer: CKContainer
        if let containerID = CloudKitConfigurationService.getContainerID() {
            ckContainer = CKContainer(identifier: containerID)
        } else {
            ckContainer = CKContainer.default()
        }
        do {
            return try await ckContainer.accountStatus()
        } catch {
            Logger.app(category: "CloudKitHealthCheck")
                .warning("accountStatus failed: \(error.localizedDescription)")
            return nil
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
