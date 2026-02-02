import Foundation
import EventKit
import SwiftData
import Combine

/// Service that syncs reminders with Apple's Reminders app via EventKit.
/// Only syncs reminders from a specific Reminders list configured by the user.
@MainActor
class ReminderSyncService: ObservableObject {
    static let shared = ReminderSyncService()
    
    private let eventStore = EKEventStore()
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
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

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
        // `deinit` is not MainActor-isolated; schedule cleanup on the main actor.
        stopObservingChanges()
    }
    
    /// Request access to Reminders
    func requestAuthorization() async throws -> Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                // Request must be called on main thread
                DispatchQueue.main.async {
                    self.eventStore.requestFullAccessToReminders { granted, error in
                        // Update status
                        Task { @MainActor in
                            self.authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
                            
                            // Start observing if access was granted and sync is configured
                            if granted && self.syncListName != nil {
                                self.startObservingChanges()
                            }
                        }
                        
                        // Handle completion - check for error first
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if granted {
                            continuation.resume(returning: true)
                        } else {
                            // Access denied
                            continuation.resume(returning: false)
                        }
                    }
                }
            }
        } else {
            // Fallback for older versions
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                DispatchQueue.main.async {
                    self.eventStore.requestAccess(to: .reminder) { granted, error in
                        Task { @MainActor in
                            self.authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
                            
                            // Start observing if access was granted and sync is configured
                            if granted && self.syncListName != nil {
                                self.startObservingChanges()
                            }
                        }
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        }
    }
    
    /// Check if we have full access to reminders
    private var hasFullAccess: Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            return authorizationStatus == .fullAccess
        } else {
            return authorizationStatus == .authorized
        }
    }
    
    // MARK: - Safe Data Transfer
    
    /// A Sendable struct to transport data safely from the non-isolated EventKit closure
    /// to the MainActor context, avoiding data race errors with EKReminder.
    private struct ReminderSyncData: Sendable {
        let title: String
        let notes: String?
        let dueDateComponents: DateComponents?
        let isCompleted: Bool
        let completionDate: Date?
        let creationDate: Date?
        let lastModifiedDate: Date?
        let calendarItemIdentifier: String
    }
    
    /// Sync reminders from the configured Reminders list
    /// This should be called when the user has configured a sync list and wants to pull reminders
    /// - Parameter force: If true, bypasses the throttle interval (use for explicit user actions like "Sync Now")
    func syncReminders(force: Bool = false) async throws {
        // Throttle: Skip if called too soon (within 10 minutes of last sync)
        // This prevents redundant syncing when the view appears multiple times
        // Can be bypassed with force=true for explicit user actions
        let throttleInterval: TimeInterval = 10 * 60 // 10 minutes
        if !force, let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) < throttleInterval {
            return // Skip sync - called too soon
        }

        // Update sync status
        isSyncing = true
        lastSyncError = nil

        do {
            try await performSync()
            // Update status on success
            lastSuccessfulSync = Date()
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
            isSyncing = false
            throw error
        }

        isSyncing = false
    }

    /// Internal sync implementation
    private func performSync() async throws {
        // Check authorization
        guard hasFullAccess else {
            throw ReminderSyncError.notAuthorized
        }

        // Check if modelContext is available
        guard let modelContext = modelContext else {
            throw ReminderSyncError.modelContextUnavailable
        }

        // Check if sync is configured (prefer identifier, fall back to name for migration)
        guard syncListIdentifier != nil || (syncListName != nil && !syncListName!.isEmpty) else {
            throw ReminderSyncError.noSyncListConfigured
        }

        // Find the target calendar (Reminders list) - prefer identifier lookup
        let targetCalendar: EKCalendar?
        if let identifier = syncListIdentifier {
            targetCalendar = findReminderList(byIdentifier: identifier)
        } else if let name = syncListName {
            targetCalendar = findReminderList(named: name)
        } else {
            targetCalendar = nil
        }

        guard let targetCalendar else {
            throw ReminderSyncError.listNotFound(syncListName ?? "Unknown")
        }

        // Fetch all reminders from the target list
        let predicate = eventStore.predicateForReminders(in: [targetCalendar])

        // Use the Sendable DTO to retrieve data safely
        let ekRemindersData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ReminderSyncData]?, Error>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                guard let reminders = reminders else {
                    continuation.resume(returning: nil)
                    return
                }

                // Map to Sendable struct inside the closure
                let safeData = reminders.map { reminder in
                    ReminderSyncData(
                        title: reminder.title ?? "Untitled",
                        notes: reminder.notes,
                        dueDateComponents: reminder.dueDateComponents,
                        isCompleted: reminder.isCompleted,
                        completionDate: reminder.completionDate,
                        creationDate: reminder.creationDate,
                        lastModifiedDate: reminder.lastModifiedDate,
                        calendarItemIdentifier: reminder.calendarItemIdentifier
                    )
                }
                continuation.resume(returning: safeData)
            }
        }

        guard let syncData = ekRemindersData else {
            return
        }

        // Get all existing reminders from our database that were synced from this calendar
        let existingReminders = try fetchAllReminders()
        // Use uniquingKeysWith to handle potential duplicates from CloudKit sync
        let existingByEKID = Dictionary<String, Reminder>(
            existingReminders.compactMap { rem -> (String, Reminder)? in
                guard let ekID = rem.eventKitReminderID else { return nil }
                return (ekID, rem)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Sync each reminder using the safe data
        var syncedCount = 0
        for data in syncData {
            if let existing = existingByEKID[data.calendarItemIdentifier] {
                // Update existing reminder (handles re-uncompleted reminders too)
                updateReminder(existing, from: data)
                syncedCount += 1
            } else {
                // Create new reminder
                let newReminder = createReminder(from: data, calendarID: targetCalendar.calendarIdentifier)
                modelContext.insert(newReminder)
                syncedCount += 1
            }
        }

        // Delete reminders that no longer exist in EventKit (orphan cleanup)
        let currentEKIDs = Set(syncData.map { $0.calendarItemIdentifier })
        for existing in existingReminders {
            if let ekID = existing.eventKitReminderID,
               !currentEKIDs.contains(ekID),
               existing.eventKitCalendarID == targetCalendar.calendarIdentifier {
                // Reminder was deleted in EventKit - remove from local database
                modelContext.delete(existing)
            }
        }

        try modelContext.save()

        // Update last sync time after successful sync
        lastSyncTime = Date()
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
        return calendars.map { $0.title }
    }

    // MARK: - Private Helpers

    private func findReminderList(named name: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .reminder)
        return calendars.first { $0.title == name }
    }

    private func findReminderList(byIdentifier identifier: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .reminder)
        return calendars.first { $0.calendarIdentifier == identifier }
    }
    
    private func fetchAllReminders() throws -> [Reminder] {
        guard let modelContext = modelContext else {
            return []
        }
        let descriptor = FetchDescriptor<Reminder>()
        return try modelContext.fetch(descriptor)
    }
    
    private func createReminder(from data: ReminderSyncData, calendarID: String) -> Reminder {
        let reminder = Reminder(
            title: data.title,
            notes: data.notes,
            dueDate: data.dueDateComponents?.date,
            isCompleted: data.isCompleted,
            completedAt: data.completionDate,
            createdAt: data.creationDate ?? Date(),
            updatedAt: data.lastModifiedDate ?? Date(),
            eventKitReminderID: data.calendarItemIdentifier,
            eventKitCalendarID: calendarID,
            lastSyncedAt: Date()
        )
        return reminder
    }
    
    private func updateReminder(_ reminder: Reminder, from data: ReminderSyncData) {
        reminder.title = data.title
        reminder.notes = data.notes
        reminder.dueDate = data.dueDateComponents?.date
        reminder.isCompleted = data.isCompleted
        reminder.completedAt = data.completionDate
        reminder.updatedAt = data.lastModifiedDate ?? Date()
        reminder.lastSyncedAt = Date()
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
                guard let self = self else { return }
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
        pendingChangeTask?.cancel()
        pendingChangeTask = nil
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
        guard syncListIdentifier != nil || (syncListName != nil && !syncListName!.isEmpty) else { return }
        guard hasFullAccess else { return }
        guard modelContext != nil else { return }
        
        // Debounce: Only sync if we haven't synced recently (within last 30 seconds)
        // This prevents excessive syncing during rapid iCloud background updates, preserving battery life
        // The logic guarantees a sync happens eventually: once 30 seconds pass since last sync, the next change will trigger a sync
        if let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) < 30.0 {
            return
        }
        
        do {
            try await syncReminders()
            lastSyncTime = Date()
        } catch {
            // Silently log errors for automatic sync (user can manually sync if needed)
            #if DEBUG
            print("ReminderSyncService: Automatic sync failed: \(error.localizedDescription)")
            #endif
        }
    }
    
    private var lastSyncTime: Date?

    /// Published sync status for UI visibility
    @Published var lastSuccessfulSync: Date?
    @Published var lastSyncError: String?
    @Published var isSyncing: Bool = false

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
