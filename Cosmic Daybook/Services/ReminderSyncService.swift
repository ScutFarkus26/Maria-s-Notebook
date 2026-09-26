import Foundation
import CoreData
import EventKit
import OSLog

/// Sendable DTO used to move reminder data from EventKit callbacks.
struct ReminderSyncData: Sendable {
    let title: String
    let notes: String?
    let dueDateComponents: DateComponents?
    let isCompleted: Bool
    let completionDate: Date?
    let creationDate: Date?
    let lastModifiedDate: Date?
    let calendarItemIdentifier: String
}

/// Service that syncs reminders with Apple's Reminders app via EventKit.
/// Only syncs reminders from a specific Reminders list configured by the user.
@Observable
final class ReminderSyncService {
    private static let logger = Logger.reminders
    static let shared = ReminderSyncService()

    /// Created on first use, not with the service: Apple calls an event store
    /// slow to set up, and the Mac made this one at every launch even with
    /// no list chosen.
    @ObservationIgnored private(set) lazy var eventStore = EKEventStore()
    var managedObjectContext: NSManagedObjectContext?

    /// Where the list choice is kept; tests pass their own suite.
    private let defaults: UserDefaults

    /// The identifier of the Reminders list to sync from (more robust than name)
    /// If nil, syncing is disabled
    var syncListIdentifier: String? {
        didSet {
            defaults.set(syncListIdentifier, forKey: UserDefaultsKeys.reminderSyncListIdentifier)
            // A new list choice lifts a pause for a missing list; listening
            // resumes below and the new choice is tried once.
            let retryAfterPause = changeListening.resume()
            // Restart observation if sync is enabled/disabled
            Task {
                if self.syncListIdentifier != nil && self.hasFullAccess {
                    self.startObservingChanges()
                    // A sync already running (a name lookup backfilling the
                    // identifier sets this too) settles the pause itself.
                    if retryAfterPause && !self.isSyncing {
                        await self.handleEventStoreChanged()
                    }
                } else {
                    self.storeChangeObserver.stop()
                }
            }
        }
    }

    /// The display name of the Reminders list (for UI display only)
    /// Stored alongside identifier for convenience
    var syncListName: String? {
        didSet {
            defaults.set(syncListName, forKey: UserDefaultsKeys.reminderSyncListName)
        }
    }

    /// Whether EventKit access has been authorized
    var authorizationStatus: EKAuthorizationStatus = .notDetermined

    // MARK: - Change Observation
    private let storeChangeObserver = EventKitChangeObserver()

    /// Paused while the configured list is missing; see `ReminderChangeListening`.
    @ObservationIgnored private var changeListening = ReminderChangeListening()

    init(context: NSManagedObjectContext? = nil, defaults: UserDefaults = .standard) {
        self.managedObjectContext = context
        self.defaults = defaults
        self.syncListIdentifier = defaults.string(forKey: UserDefaultsKeys.reminderSyncListIdentifier)
        self.syncListName = defaults.string(forKey: UserDefaultsKeys.reminderSyncListName)
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)

        // Migrate from name-only storage to identifier-based storage
        migrateToIdentifierBasedStorage()

        // Start observing if we have access and a sync list configured
        if syncListIdentifier != nil && hasFullAccess {
            startObservingChanges()
        }
    }

    /// Migrate from legacy name-based storage to identifier-based storage
    private func migrateToIdentifierBasedStorage() {
        // If we have a name but no identifier, try to find the calendar and store its identifier
        if syncListIdentifier == nil, let name = syncListName, !name.isEmpty, hasFullAccess {
            if let calendar = findReminderList(named: name) {
                syncListIdentifier = calendar.calendarIdentifier
            }
        }
    }
    
    deinit {
        // `deinit` is not MainActor-isolated
        // The stopObservingChangesOnMainActor method is already designed to handle cleanup safely
        // We can't await in deinit, but the Task will ensure cleanup happens asynchronously
        // NotificationCenter's removeObserver is safe to call from any thread
        stopObservingChanges()
    }
    
    /// Request access to Reminders
    func requestAuthorization() async throws -> Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            // swiftlint:disable closure_parameter_position
            let granted = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Bool, Error>) in
                // swiftlint:enable closure_parameter_position
                self.eventStore.requestFullAccessToReminders { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            
            // Update status and start observing on main actor
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            // Identifier-first, but fall back to a legacy name-only configuration
            // (stored before identifiers existed) so auto-observation still starts
            // on first grant. Mirrors startObservingChanges' own guard
            // (identifier OR name).
            if granted && (syncListIdentifier != nil || syncListName != nil) {
                startObservingChanges()
            }

            return granted
        } else {
            // swiftlint:disable closure_parameter_position
            let granted = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Bool, Error>) in
                // swiftlint:enable closure_parameter_position
                self.eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            
            // Update status and start observing on main actor
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            // Identifier-first, but fall back to a legacy name-only configuration
            // (stored before identifiers existed) so auto-observation still starts
            // on first grant. Mirrors startObservingChanges' own guard
            // (identifier OR name).
            if granted && (syncListIdentifier != nil || syncListName != nil) {
                startObservingChanges()
            }

            return granted
        }
    }
    
    /// Check if we have full access to reminders
    var hasFullAccess: Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            return authorizationStatus == .fullAccess
        } else {
            return authorizationStatus == .authorized
        }
    }
    
    /// Represents a Reminders list with both identifier and display name
    struct ReminderListInfo: Identifiable, Hashable, Sendable {
        let identifier: String
        let name: String
        var id: String { identifier }

        nonisolated static func == (lhs: ReminderListInfo, rhs: ReminderListInfo) -> Bool {
            lhs.identifier == rhs.identifier && lhs.name == rhs.name
        }

        nonisolated func hash(into hasher: inout Hasher) {
            hasher.combine(identifier)
            hasher.combine(name)
        }
    }

    /// Get all available Reminders lists with their identifiers
    func getAvailableReminderListsWithIdentifiers() -> [ReminderListInfo] {
        guard hasFullAccess else {
            return []
        }

        let calendars = eventStore.calendars(for: .reminder)
        return calendars.map { ReminderListInfo(identifier: $0.calendarIdentifier, name: $0.title) }
    }

    // MARK: - Private Helpers

    func findReminderList(named name: String) -> EKCalendar? {
        Self.reminderList(named: name, in: eventStore.calendars(for: .reminder))
    }

    /// The first of `lists` titled `name`.
    static func reminderList(named name: String, in lists: [EKCalendar]) -> EKCalendar? {
        // Case/diacritic-insensitive: list names are user-typed in Reminders and
        // legacy stored names may not match the list's exact casing.
        lists.first {
            $0.title.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    // MARK: - Automatic Syncing
    
    /// Start observing EventKit changes for automatic syncing
    private func startObservingChanges() {
        guard changeListening.shouldListen(
            hasFullAccess: hasFullAccess,
            isListConfigured: syncListIdentifier != nil || syncListName != nil
        ) else { return }

        storeChangeObserver.start(observing: eventStore) { [weak self] in
            await self?.handleEventStoreChanged()
        }
    }

    /// True while store changes are being listened for.
    var isObservingChanges: Bool { storeChangeObserver.isObserving }

    /// True while a missing list has paused listening.
    var isChangeObservationPaused: Bool { changeListening.isPaused }

    /// Stops listening for store changes after a sync found no list for the
    /// setting (Danny, 2026-09-25): until the setting changes, a store change
    /// would only run the same failing sync again. Logged once per pause.
    func pauseChangeObservationForMissingList() {
        guard changeListening.pause() else { return }
        storeChangeObserver.stop()
        Self.logger.notice("Reminders list not found; syncing on changes paused until the list setting changes")
    }

    /// Listens again after a sync found the list, whether it came back in
    /// Reminders or a refresh had hidden it for a moment.
    func resumeChangeObservationIfPaused() {
        guard changeListening.resume() else { return }
        startObservingChanges()
    }

    /// Stop observing EventKit changes
    /// Safe to call from nonisolated contexts (e.g. `deinit`)
    private nonisolated func stopObservingChanges() {
        Task { @MainActor [weak self] in
            self?.storeChangeObserver.stop()
        }
    }
    
    /// Handle EventKit store changes by syncing reminders, once the store has
    /// gone quiet (`EventKitChangeObserver`)
    func handleEventStoreChanged() async {
        // Only sync if we have a configured list (identifier or name) and access
        guard syncListIdentifier != nil || (syncListName.map { !$0.isEmpty } ?? false) else { return }
        guard hasFullAccess else { return }
        guard managedObjectContext != nil else { return }
        
        // `syncReminders` skips a call within 10 minutes of the last sync, so
        // the time is recorded only when a sync ran. Recording it after a
        // skipped one (as this did, behind a 30-second check the throttle
        // covers) pushed the next sync back on every change: while the list
        // kept changing at least every 10 minutes, no unforced sync ran at all.
        do {
            if try await syncReminders() {
                lastSyncTime = Date()
            }
        } catch let error as ReminderSyncError where error.isConfigurationIssue {
            // Stale/missing configuration (e.g. list deleted in Reminders) —
            // shown in Settings; not an error worth flagging on every change.
            Self.logger.notice("Automatic sync skipped: \(error.localizedDescription)")
        } catch {
            // Silently log errors for automatic sync (user can manually sync if needed)
            Self.logger.warning("Automatic sync failed: \(error.localizedDescription)")
        }
    }
    
    /// When the last sync ran; the 10-minute throttle reads it.
    var lastSyncTime: Date?

    /// Sync status for UI visibility
    var lastSuccessfulSync: Date?
    var lastSyncError: String?
    var isSyncing: Bool = false

    // MARK: - Two-Way Sync: Update EventKit from Local Changes (Core Data)

    /// Update a reminder's completion status in EventKit (Core Data)
    /// Call this when the user toggles completion in the app
    func updateReminderCompletionInEventKit(_ reminder: CDReminder) async throws {
        guard hasFullAccess else {
            throw ReminderSyncError.notAuthorized
        }

        guard let ekID = reminder.eventKitReminderID else {
            // Not synced from EventKit, nothing to update
            return
        }

        // Fetch the EKReminder by identifier
        guard let ekReminder = eventStore.calendarItem(withIdentifier: ekID) as? EKReminder else {
            // CDReminder no longer exists in EventKit
            return
        }

        // Update completion status
        ekReminder.isCompleted = reminder.isCompleted
        ekReminder.completionDate = reminder.completedAt

        // Save to EventKit
        try eventStore.save(ekReminder, commit: true)
    }

}

enum ReminderSyncError: LocalizedError, Equatable {
    case notAuthorized
    case noSyncListConfigured
    case listNotFound(String)
    case modelContextUnavailable

    /// True for errors caused by app/user configuration state (access not granted,
    /// no list chosen, or the chosen list no longer exists in Reminders) rather
    /// than an actual sync failure. Automatic sync call sites log these quietly;
    /// Settings still surfaces them to the user.
    var isConfigurationIssue: Bool {
        switch self {
        case .notAuthorized, .noSyncListConfigured, .listNotFound:
            return true
        case .modelContextUnavailable:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Reminders access has not been granted. Please authorize access in Settings."
        case .noSyncListConfigured:
            return "No Reminders list has been configured for syncing."
        case .listNotFound(let name):
            return "Reminders list '\(name)' not found. Please check the list name in settings."
        case .modelContextUnavailable:
            return "Database context is not available. Please try again."
        }
    }
}
