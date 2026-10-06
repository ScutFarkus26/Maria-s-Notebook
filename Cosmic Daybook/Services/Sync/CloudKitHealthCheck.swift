import CloudKit
import Foundation
import OSLog
import SwiftUI

/// Service responsible for monitoring CloudKit health and availability
@Observable
final class CloudKitHealthCheck {
    // MARK: - Observable State
    
    /// Overall sync health status
    private(set) var syncHealth: SyncHealth = .unknown
    
    /// Whether iCloud account is available
    private(set) var isICloudAvailable: Bool = true

    /// True once CloudKit itself has answered (`accountStatus`). Until then
    /// `isICloudAvailable` is only the iCloud Drive hint, which is off
    /// whenever iCloud Drive is, so it can't say "signed out" on its own.
    private(set) var isAccountStatusKnown = false

    /// CloudKit says no usable iCloud account is signed in: sync health reads
    /// as offline, and Settings says "iCloud isn't available. Sign in…".
    var isSignedOut: Bool { isAccountStatusKnown && !isICloudAvailable }

    /// The signed-in account's user record name, the last time one was read
    /// this session: tells a switch to another Apple Account from a sign-in.
    private var lastUserRecordName: String?

    // MARK: - Types

    /// What `observeICloudChanges` reports.
    struct AccountChange: Equatable, Sendable {
        let isAvailable: Bool
        /// Another Apple Account than the one seen before this session.
        let isDifferentAccount: Bool
    }

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
    }
    
    // MARK: - Private State

    /// The `.CKAccountChanged` listener; there is only ever one (see `listenForAccountChanges`).
    private(set) var iCloudAccountTask: Task<Void, Never>?
    private var pendingICloudTask: Task<Void, Never>?
    private var iCloudChangeContinuation: AsyncStream<AccountChange>.Continuation?
    
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
    
    /// Observe iCloud account status changes as an AsyncStream: availability
    /// flips, CloudKit's first answer, and a switch to another account.
    func observeICloudChanges() -> AsyncStream<AccountChange> {
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
        listenForAccountChanges()

        // Replace the synchronous init-time hint with the authoritative status.
        pendingICloudTask?.cancel()
        pendingICloudTask = Task { [weak self] in
            await self?.handleICloudAccountChange()
        }
    }

    /// (Re)starts the `.CKAccountChanged` listener. Every reconfigure of
    /// `CloudKitSyncStatusService` calls this again, and the old listener used
    /// to be overwritten without being cancelled, so each call left one more
    /// running for the rest of the session. It is cancelled first now, so a
    /// call replaces the listener instead of adding one.
    func listenForAccountChanges() {
        iCloudAccountTask?.cancel()
        iCloudAccountTask = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: .CKAccountChanged)
                .map { _ in () }
            for await _ in changes {
                guard let self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingICloudTask?.cancel()
                self.pendingICloudTask = Task { [weak self] in
                    await self?.handleICloudAccountChange()
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
    ///   - storeFailure: The most severe outstanding per-store failure, if any.
    ///     A stopped store is an error even while the other store syncs or has
    ///     just succeeded; a retrying one is a warning once nothing else is wrong.
    func updateSyncHealth(
        isSyncing: Bool,
        lastSuccessfulSync: Date?,
        lastSyncError: String?,
        isNetworkAvailable: Bool,
        isEnabled: Bool,
        isActive: Bool,
        storeFailure: StoreSyncFailure? = nil
    ) {
        guard isEnabled, isActive, isNetworkAvailable, !isSignedOut else {
            syncHealth = .offline
            return
        }
        if let storeFailure, storeFailure.severity == .stopped {
            syncHealth = .error(storeFailure.message)
            return
        }
        if isSyncing { syncHealth = .syncing; return }

        if let health = syncHealthFromError(lastSyncError, lastSuccessfulSync: lastSuccessfulSync) {
            syncHealth = health
            return
        }
        if storeFailure != nil {
            syncHealth = .warning
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
        let available = status == .available
        let recordName = available ? await Self.fetchUserRecordName() : nil
        if let change = recordAccountStatus(available: available, userRecordName: recordName) {
            iCloudChangeContinuation?.yield(change)
        }
    }

    /// Takes CloudKit's answer. Returns what to report: availability that
    /// flipped, the first answer this session (the Drive hint may have been
    /// right, but health still has to hear it), or another account's record
    /// name than the last one read. Nil when nothing changed.
    func recordAccountStatus(available: Bool, userRecordName: String?) -> AccountChange? {
        let wasAvailable = isICloudAvailable
        let wasKnown = isAccountStatusKnown
        let isDifferentAccount = Self.isDifferentAccount(previous: lastUserRecordName, current: userRecordName)
        isICloudAvailable = available
        isAccountStatusKnown = true
        if let userRecordName { lastUserRecordName = userRecordName }
        guard wasAvailable != available || !wasKnown || isDifferentAccount else { return nil }
        return AccountChange(isAvailable: available, isDifferentAccount: isDifferentAccount)
    }

    /// A different record name than the last one read: another Apple
    /// Account, whether switched directly or signed out and in again as
    /// someone else. Either name unknown says nothing.
    nonisolated static func isDifferentAccount(previous: String?, current: String?) -> Bool {
        guard let previous, let current else { return false }
        return previous != current
    }

    /// The signed-in account's user record name; nil when it can't be read
    /// (offline, say), which leaves the last one in place.
    private static func fetchUserRecordName() async -> String? {
        do {
            return try await CloudKitConfigurationService.container.userRecordID().recordName
        } catch {
            Logger.cloudKitHealthCheck.warning("userRecordID failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Queries CloudKit for the account status of the app's container.
    /// Returns nil on error (status unknown — keep the current value rather
    /// than flapping the UI on a transient failure).
    private static func fetchAccountStatus() async -> CKAccountStatus? {
        do {
            return try await CloudKitConfigurationService.container.accountStatus()
        } catch {
            Logger.cloudKitHealthCheck
                .warning("accountStatus failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private nonisolated func stopObserving() {
        Task { @MainActor [weak self] in
            self?.pendingICloudTask?.cancel()
            self?.pendingICloudTask = nil
            
            self?.iCloudAccountTask?.cancel()
            self?.iCloudAccountTask = nil
        }
    }
}
