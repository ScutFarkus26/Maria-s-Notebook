// swiftlint:disable file_length
import Foundation
import EventKit
import SwiftData
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

// swiftlint:disable type_body_length
/// Service that syncs reminders with Apple's Reminders app via EventKit.
/// Only syncs reminders from a specific Reminders list configured by the user.
@Observable
@MainActor
final class ReminderSyncService {
    private static let logger = Logger.reminders
    static let shared = ReminderSyncService()
    
    let eventStore = EKEventStore()
    var modelContext: ModelContext?

    /// The identifier of the Reminders list to sync from (more robust than name)
    /// If nil, syncing is disabled
    var syncListIdentifier: String? {
        didSet {
            UserDefaults.standard.set(syncListIdentifier, forKey: "ReminderSync.syncListIdentifier")
            // Restart observation if sync is enabled/disabled
            Task { @MainActor in
                if self.syncListIdentifier != nil && self.hasFullAccess {
                    self.startObservingChanges()
                } else {
                    self.stopObservingChangesOnMainActor()
                }
            }
        }
    }

    /// The display name of the Reminders list (for UI display only)
    /// Stored alongside identifier for convenience
    var syncListName: String? {
        didSet {
            UserDefaults.standard.set(syncListName, forKey: "ReminderSync.syncListName")
        }
    }

    /// Whether EventKit access has been authorized
    var authorizationStatus: EKAuthorizationStatus = .notDetermined

    // MARK: - Change Observation
    private var changeObserver: NSObjectProtocol?
    private var isObserving = false
    private var pendingChangeTask: Task<Void, Never>?

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        self.syncListIdentifier = UserDefaults.standard.string(forKey: "ReminderSync.syncListIdentifier")
        self.syncListName = UserDefaults.standard.string(forKey: "ReminderSync.syncListName")
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
            if granted && syncListName != nil {
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
            if granted && syncListName != nil {
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

    /// Get all available Reminders lists (legacy, returns names only)
    func getAvailableReminderLists() -> [String] {
        guard hasFullAccess else {
            return []
        }

        let calendars = eventStore.calendars(for: .reminder)
        return calendars.map(\.title)
    }

    // MARK: - Private Helpers

    func findReminderList(named name: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .reminder)
        return calendars.first { $0.title == name }
    }

    func findReminderList(byIdentifier identifier: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .reminder)
        return calendars.first { $0.calendarIdentifier == identifier }
    }
    
    // MARK: - Automatic Syncing
    
    /// Start observing EventKit changes for automatic syncing
    private func startObservingChanges() {
        guard !isObserving else { return }
        guard hasFullAccess else { return }
        guard syncListIdentifier != nil || syncListName != nil else { return }
        
        // Observe EventKit store changes
        // Note: EKEventStoreChangedNotification is posted when reminders/events change
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingChangeTask?.cancel()
                self.pendingChangeTask = Task { @MainActor [weak self] in
                    await self?.handleEventStoreChanged()
                }
            }
        }

        isObserving = true
    }
    
    /// Stop observing EventKit changes (MainActor implementation)
    @MainActor
    private func stopObservingChangesOnMainActor() {
        // Cancel any pending sync tasks
        pendingChangeTask?.cancel()
        pendingChangeTask = nil
        
        // Remove notification observer - safe to call even if observer is nil
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
        
        isObserving = false
    }

    /// Stop observing EventKit changes
    /// Safe to call from nonisolated contexts (e.g. `deinit`)
    private nonisolated func stopObservingChanges() {
        Task { @MainActor [weak self] in
            self?.stopObservingChangesOnMainActor()
        }
    }
    
    /// Handle EventKit store changes by syncing reminders
    private func handleEventStoreChanged() async {
        // Only sync if we have a configured list (identifier or name) and access
        guard syncListIdentifier != nil || (syncListName.map { !$0.isEmpty } ?? false) else { return }
        guard hasFullAccess else { return }
        guard modelContext != nil else { return }
        
        // Debounce: Only sync if we haven't synced recently (within last 30 seconds)
        // This prevents excessive syncing during rapid iCloud background updates,
        // preserving battery life. The logic guarantees a sync happens eventually:
        // once 30 seconds pass since last sync, the next change triggers a sync.
        if let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) < 30.0 {
            return
        }
        
        do {
            try await syncReminders()
            lastSyncTime = Date()
        } catch {
            // Silently log errors for automatic sync (user can manually sync if needed)
            Self.logger.warning("Automatic sync failed: \(error.localizedDescription)")
        }
    }
    
    var lastSyncTime: Date?

    /// Sync status for UI visibility
    var lastSuccessfulSync: Date?
    var lastSyncError: String?
    var isSyncing: Bool = false

    // MARK: - Two-Way Sync: Update EventKit from Local Changes

    /// Update a reminder's completion status in EventKit
    /// Call this when the user toggles completion in the app
    func updateReminderCompletionInEventKit(_ reminder: Reminder) async throws {
        guard hasFullAccess else {
            throw ReminderSyncError.notAuthorized
        }

        guard let ekID = reminder.eventKitReminderID else {
            // Not synced from EventKit, nothing to update
            return
        }

        // Fetch the EKReminder by identifier
        guard let ekReminder = eventStore.calendarItem(withIdentifier: ekID) as? EKReminder else {
            // Reminder no longer exists in EventKit
            return
        }

        // Update completion status
        ekReminder.isCompleted = reminder.isCompleted
        ekReminder.completionDate = reminder.completedAt

        // Save to EventKit
        try eventStore.save(ekReminder, commit: true)
    }
}
// swiftlint:enable type_body_length

enum ReminderSyncError: LocalizedError, Equatable {
    case notAuthorized
    case noSyncListConfigured
    case listNotFound(String)
    case modelContextUnavailable

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
