import Foundation
import EventKit
import SwiftData
import Combine

/// Service that syncs reminders with Apple's Reminders app via EventKit.
/// Only syncs reminders from a specific Reminders list configured by the user.
@MainActor
class ReminderSyncService: ObservableObject {
    private let eventStore = EKEventStore()
    var modelContext: ModelContext
    
    /// The name of the Reminders list to sync from
    /// If nil, syncing is disabled
    var syncListName: String? {
        didSet {
            UserDefaults.standard.set(syncListName, forKey: "ReminderSync.syncListName")
        }
    }
    
    /// Whether EventKit access has been authorized
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.syncListName = UserDefaults.standard.string(forKey: "ReminderSync.syncListName")
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
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
    func syncReminders() async throws {
        // Check authorization
        guard hasFullAccess else {
            throw ReminderSyncError.notAuthorized
        }
        
        // Check if sync is configured
        guard let listName = syncListName, !listName.isEmpty else {
            throw ReminderSyncError.noSyncListConfigured
        }
        
        // Find the target calendar (Reminders list)
        guard let targetCalendar = findReminderList(named: listName) else {
            throw ReminderSyncError.listNotFound(listName)
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
        
        // Get all existing reminders from our database
        let existingReminders = try fetchAllReminders()
        let existingByEKID = Dictionary<String, Reminder>(uniqueKeysWithValues: existingReminders.compactMap { rem in
            guard let ekID = rem.eventKitReminderID else { return nil }
            return (ekID, rem)
        })
        
        // Sync each reminder using the safe data
        var syncedCount = 0
        for data in syncData {
            if let existing = existingByEKID[data.calendarItemIdentifier] {
                // Update existing reminder
                updateReminder(existing, from: data)
                syncedCount += 1
            } else {
                // Create new reminder
                let newReminder = createReminder(from: data, calendarID: targetCalendar.calendarIdentifier)
                modelContext.insert(newReminder)
                syncedCount += 1
            }
        }
        
        // Mark reminders that no longer exist in EventKit as deleted
        let currentEKIDs = Set(syncData.map { $0.calendarItemIdentifier })
        for existing in existingReminders {
            if let ekID = existing.eventKitReminderID,
               !currentEKIDs.contains(ekID),
               existing.eventKitCalendarID == targetCalendar.calendarIdentifier {
                // Reminder was deleted in EventKit - mark as completed or remove
                // For now, we'll just update it to reflect it's gone
                existing.lastSyncedAt = Date()
            }
        }
        
        try modelContext.save()
    }
    
    /// Get all available Reminders lists
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
    
    private func fetchAllReminders() throws -> [Reminder] {
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
}

enum ReminderSyncError: LocalizedError {
    case notAuthorized
    case noSyncListConfigured
    case listNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Reminders access has not been granted. Please authorize access in Settings."
        case .noSyncListConfigured:
            return "No Reminders list has been configured for syncing."
        case .listNotFound(let name):
            return "Reminders list '\(name)' not found. Please check the list name in settings."
        }
    }
}
