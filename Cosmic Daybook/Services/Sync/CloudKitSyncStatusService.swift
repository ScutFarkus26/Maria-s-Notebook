import Foundation
import SwiftUI
import CloudKit
import CoreData
import OSLog

/// Service that monitors CloudKit sync activity and provides status information.
/// Tracks global sync state through Core Data notifications from
/// NSPersistentCloudKitContainer.
@Observable
final class CloudKitSyncStatusService {
    static let logger = Logger.sync
    static let shared = CloudKitSyncStatusService()

    // MARK: - Observable State

    /// Whether a sync operation is currently in progress
    var isSyncing: Bool = false

    /// The last time a successful sync completed
    var lastSuccessfulSync: Date?

    /// The last sync error, in plain words for the screen, if any.
    var lastSyncError: String?

    /// The raw text behind `lastSyncError` (the system error with its domain
    /// and code), for the Details disclosure and `sync_status`.
    var lastSyncErrorDetail: String?

    /// What kind of problem `lastSyncError` is, so coming back online or
    /// signing in clears the right one without reading its wording.
    /// (The shown error's helpers are in `CloudKitSyncStatusService+ShownError`.)
    var lastSyncErrorKind: SyncErrorKind?

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

    /// CloudKit says no usable iCloud account is signed in (not just the
    /// iCloud Drive hint `isICloudAvailable` starts from).
    var isICloudSignedOut: Bool {
        healthCheck.isSignedOut
    }

    /// Timestamp when the service was initialized (used for startup grace period)
    let initializationTime: Date = Date()

    /// Number of pending local saves waiting for CloudKit confirmation.
    var pendingLocalChanges: Int { pendingSyncCount }

    /// Retry attempt diagnostics for settings UI.
    var retryAttempt: Int { retryLogic.retryAttempt }

    /// Maximum retry attempts for settings UI.
    var maxRetryAttempts: Int { retryLogic.maxRetryCount }

    /// Whether a retry is currently scheduled.
    var hasPendingRetry: Bool { retryLogic.hasPendingRetry }

    /// True when one of `NSPersistentCloudKitContainer`'s mirroring delegates
    /// failed: a setup-event failure (not one for want of an iCloud account or
    /// a network), `NSCocoaErrorDomain` 134421 / 134406, or "never
    /// successfully initialized". Apple documents no recovery from these, so
    /// it holds until the store that set it imports or exports successfully
    /// again. One flag for the screens, kept per store underneath
    /// (`stoppedSince`): every source names its store, an attach to the
    /// classroom share included (`markMirroringStopped(byAttachToStoreWithIdentifier:)`;
    /// bug hunt 2026-10-09, #2). `storeHealth` names the store and the cause
    /// (`SyncStoppedAdvice`): re-downloading fixes a damaged local copy, but
    /// not a server refusal such as a schema missing from Production, where
    /// it would throw away the unsent changes.
    var mirroringDelegateFailed: Bool { !stoppedSince.isEmpty }

    /// The stores whose mirroring delegates died, and since when. Each leaves
    /// on a successful import or export of its own that started after that
    /// (`clearMirroringStopped`). Written only by `markMirroringStopped`,
    /// `clearMirroringStopped` and `resetForNewAccount`.
    var stoppedSince: [SyncedStore: Date] = [:]

    /// True once a CloudKit setup failed with no iCloud account signed in at
    /// all (the account status says `noAccount`): nothing is filed into the
    /// classroom share until the app is reopened (Danny's call, bug hunt
    /// 2026-10-09, #2; `shareFilingHold`). Kept for the life of the process:
    /// another account signing in or a store's later success doesn't clear it.
    var shareFilingPausedUntilReopen = false

    /// Stores whose setup failed for want of a ready iCloud account, by store
    /// identifier, and how far each has come back (`followAccountReadiness`).
    var accountNotReadyStores: [String: AccountReadiness] = [:]

    /// CloudKit's account status, asked after a setup failed for want of an
    /// account; a test sets its own.
    @ObservationIgnored var accountStatus: @MainActor () async throws -> CKAccountStatus = {
        try await CloudKitConfigurationService.container.accountStatus()
    }

    /// Failed setup/import/export events per store (notebook, classroom share)
    /// that no later success of the same kind on the same store has cleared.
    /// One store can stop while the other keeps syncing, and the other's
    /// successes must not hide it — `lastSyncError` is cleared by any success.
    var storeHealth = CloudKitStoreHealth()

    /// Names the store an event's `storeIdentifier` belongs to. Nil reads the
    /// configured stack's private and shared stores; tests supply their own.
    @ObservationIgnored var syncedStoreResolver: ((String?) -> SyncedStore)?

    /// True while `NSPersistentCloudKitContainer` is performing its initial
    /// `setup` or `import` of data from iCloud. Drives the "Syncing from iCloud…"
    /// overlay so a freshly launched or freshly signed-in device shows progress
    /// instead of an empty-looking screen. Apple notes the first import on a new
    /// device "can take minutes, or longer" (TN3163). Only ever set while
    /// ``isFirstDownload`` — a device that holds its data locally must not
    /// re-show the overlay.
    var isImportingFromCloud: Bool = false

    /// Whether the private store's first download is still under way
    /// (`FirstDownloadGate`: a new device, or after Reset Local Cache).
    /// `NSPersistentCloudKitContainer` fires a `setup` event on *every* launch
    /// (and routine `import` events for incremental changes), so keying the
    /// "Syncing from iCloud…" overlay off those events made it flash on every
    /// launch; it shows only for the genuine first import, when the screen
    /// would otherwise look empty (TN3163). It used to be "never synced
    /// before", read from the last sync date, which Reset Local Cache keeps,
    /// so the overlay never showed after a reset.
    var isFirstDownload: Bool { FirstDownloadGate.isPending() }

    // MARK: - Specialized Services

    let networkMonitor = NetworkMonitoring()
    let retryLogic: SyncRetryLogic
    let healthCheck = CloudKitHealthCheck()

    // MARK: - Internal State (accessed by extensions)

    /// One task per typed message stream (remote change, store change, and
    /// the wait before the latter); cancelling it ends the stream.
    var messageObservationTasks: [Task<Void, Never>] = []
    var saveObserver: NSObjectProtocol?
    var syncStartTime: Date?
    private(set) var coreDataStack: CoreDataStack?
    var monitoredPersistentStoreCoordinator: NSPersistentStoreCoordinator? {
        coreDataStack?.container.persistentStoreCoordinator
    }
    var syncingTask: Task<Void, Never>?

    // Task tracking for notification handlers to prevent accumulation
    var pendingRemoteChangeTask: Task<Void, Never>?
    var pendingSaveTask: Task<Void, Never>?
    var pendingStoreChangeTask: Task<Void, Never>?

    /// A `lastSuccessfulSync` not yet written to UserDefaults. The defaults
    /// copy is only read at launch (initial health, the first-import overlay),
    /// so it is written at most once per `syncDatePersistInterval`, plus when
    /// the app backgrounds or quits (see `recordSuccessfulSync`).
    @ObservationIgnored var unpersistedSyncDate: Date?
    /// When the defaults copy of `lastSuccessfulSync` was last written.
    @ObservationIgnored var syncDatePersistedAt: Date?
    /// Writes `unpersistedSyncDate` once its interval is up.
    @ObservationIgnored var syncDatePersistTask: Task<Void, Never>?
    @ObservationIgnored var lifecycleObservers: [any NSObjectProtocol] = []
    static let syncDatePersistInterval: Duration = .seconds(60)

    /// Debounce that clears `isImportingFromCloud` once CloudKit import activity
    /// goes quiet. (Re)armed by `noteCloudImportActivity()`.
    var cloudImportDebounceTask: Task<Void, Never>?

    /// Pending sync count - tracks how many saves are waiting for CloudKit confirmation
    var pendingSyncCount: Int = 0

    /// Current CloudKit operation (setup/import/export/manual) if known.
    var currentOperation: String?

    /// Most recent finished CloudKit operation description.
    var lastOperation: String?

    /// Timestamp for the most recent finished operation.
    var lastOperationDate: Date?

    /// Maximum time to wait for sync confirmation before assuming success (in nanoseconds)
    let syncTimeout: Duration = TimeoutConstants.defaultSyncTimeout

    /// Quiet period after the last `.NSPersistentStoreRemoteChange` before one
    /// `handleRemoteChange` runs. CloudKit posts that notification once per
    /// imported batch — dozens a second during an import — and each handler
    /// pass writes UserDefaults and the sync history, so a burst is handled once.
    var remoteChangeDebounce: Duration = .milliseconds(500)

    /// Diagnostics: how many debounced remote-change passes have run this session.
    private(set) var remoteChangeHandlingCount = 0

    /// The CloudKit event stream: one per process, made by whichever comes
    /// first, the stores opening (`beginEarlyEventCapture`) or `configure`.
    /// Outside `messageObservationTasks`, so reconfiguring doesn't end it.
    @ObservationIgnored var cloudKitEventTask: Task<Void, Never>?
    /// False until `configure`: events that arrive before it wait in `bufferedEvents`.
    @ObservationIgnored var handlesCloudKitEvents = false
    @ObservationIgnored var bufferedEvents: [CloudKitEventValues] = []
    /// The stack whose stores opened while the events were buffered.
    @ObservationIgnored weak var earlyCaptureStack: CoreDataStack?

    // MARK: - Initialization

    init(coreDataStack: CoreDataStack? = nil, retryLogic: SyncRetryLogic = SyncRetryLogic()) {
        self.coreDataStack = coreDataStack
        self.retryLogic = retryLogic

        // Load persisted state
        let syncDateKey = UserDefaultsKeys.cloudKitLastSuccessfulSyncDate
        if let timestamp = UserDefaults.standard.object(forKey: syncDateKey) as? TimeInterval {
            lastSuccessfulSync = Date(timeIntervalSince1970: timestamp)
        }
        loadPersistedSyncError()

        // Setup network monitoring using AsyncStream
        Task { [weak self] in
            guard let self else { return }
            for await isAvailable in self.networkMonitor.observeNetworkChanges() {
                self.handleNetworkChange(isAvailable: isAvailable)
            }
        }

        // Setup iCloud account monitoring using AsyncStream
        Task { [weak self] in
            guard let self else { return }
            for await change in self.healthCheck.observeICloudChanges() {
                if change.isDifferentAccount { self.resetForNewAccount() }
                self.handleICloudAccountChange(isAvailable: change.isAvailable)
            }
        }

        observeLifecycleForSyncDateFlush()

        // Update health status after initialization
        updateSyncHealth()
    }

    deinit {
        // Cannot call @MainActor stopObserving() from nonisolated deinit.
        // Dispatch cleanup to MainActor; the specialized services will be
        // cleaned up when deallocated.
        Task { @MainActor [weak self] in
            self?.stopObserving()
        }
    }

    // MARK: - Setup

    func configure(with stack: CoreDataStack) {
        // Tear down any existing observers before reconfiguring to prevent
        // duplicate observers and stale references (Apple best practice:
        // NSCloudKitMirroringDelegate instances are not reusable)
        removeAllObservers()
        syncingTask?.cancel()
        syncingTask = nil

        // A new stack brings new mirroring delegates; the old stores' failures
        // say nothing about them. (Another window configuring with the same
        // stack must keep them.)
        if stack !== coreDataStack {
            storeHealth = CloudKitStoreHealth()
        }
        self.coreDataStack = stack
        watchForFirstDownloadIfPending()

        // CloudKit's events, saves and remote changes from now on (and the
        // events buffered since the stores opened): a setup failure at launch
        // used to land in the 2-second gap below and go unseen.
        startHandlingCloudKitEvents(for: stack)
        startObserving()
        healthCheck.startICloudAccountMonitoring()
        updateSyncHealth()

        // Only the store-change listener waits: Core Data adds and tears down
        // temporary stores during CloudKit setup, and those expected
        // teardowns aren't errors.
        messageObservationTasks.append(Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
            } catch {
                return  // Cancelled: expected during reconfiguration
            }
            self?.startObservingStoreChanges()
        })
    }

    // MARK: - Remote-change debounce

    /// Coalesces a burst of remote-change notifications into a single
    /// `handleRemoteChange` once they go quiet for `remoteChangeDebounce`.
    func scheduleRemoteChangeHandling() {
        pendingRemoteChangeTask?.cancel()
        pendingRemoteChangeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.remoteChangeDebounce)
            } catch {
                return // superseded by a newer notification
            }
            self.remoteChangeHandlingCount += 1
            self.handleRemoteChange()
        }
    }

    // MARK: - Manual Sync

    /// Triggers a save on the managed object context to push pending changes.
    /// Returns true if save succeeded, false otherwise.
    @discardableResult
    func syncNow() async -> Bool {
        guard let viewContext = coreDataStack?.viewContext else { return false }

        isSyncing = true
        syncStartTime = Date()
        currentOperation = "Manual sync"
        updateSyncHealth()
        SyncEventLogger.shared.log("cloudkit", status: "started", message: "You tapped Sync Now")

        do {
            // Use the view context so any pending local changes are actually
            // committed to the store (and thus queued for CloudKit mirroring).
            try viewContext.save()

            // Saved for iCloud to send; only a successful import or export
            // says it went (handleSuccessfulCloudKitEvent stamps and clears).
            let now = Date()
            SyncEventLogger.shared.log("cloudkit", status: "success", message: "Saved your changes for iCloud to send")

            // Keep syncing indicator briefly to show activity
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                // CancellationError or other — just proceed
            }
            isSyncing = false
            lastOperation = "Changes saved for iCloud"
            lastOperationDate = now
            currentOperation = nil
            updateSyncHealth()
            return true
        } catch {
            recordManualSyncFailure(error)
            isSyncing = false
            lastOperation = "Manual sync failed"
            lastOperationDate = Date()
            currentOperation = nil
            updateSyncHealth()
            return false
        }
    }

    // MARK: - Health Assessment

    func updateSyncHealth() {
        let isEnabled = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.enableCloudKitSync
        ) as? Bool ?? true
        let isActive = UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)

        healthCheck.updateSyncHealth(
            isSyncing: isSyncing,
            lastSuccessfulSync: lastSuccessfulSync,
            lastSyncError: lastSyncError,
            isNetworkAvailable: isNetworkAvailable,
            isEnabled: isEnabled,
            isActive: isActive,
            storeFailure: storeHealth.mostSevereFailure
        )
    }

    /// Clear any stored error state
    func clearError() {
        clearSyncErrorInMemory()
        retryLogic.resetRetryCount()
        Self.removePersistedSyncError()
        updateSyncHealth()
    }
}
