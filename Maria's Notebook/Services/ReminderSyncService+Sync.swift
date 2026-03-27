import Foundation
import OSLog
import EventKit
import SwiftData

// MARK: - Sync Logic

extension ReminderSyncService {

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
        SyncEventLogger.shared.log("reminders", status: "started", message: "Reminders sync started")

        do {
            try await performSync()
            // Update status on success
            lastSuccessfulSync = Date()
            lastSyncError = nil
            SyncEventLogger.shared.log("reminders", status: "success", message: "Reminders sync completed")
        } catch {
            lastSyncError = error.localizedDescription
            SyncEventLogger.shared.log("reminders", status: "error", message: error.localizedDescription)
            isSyncing = false
            throw error
        }

        isSyncing = false
    }

    func performSync() async throws {
        // Check authorization
        guard hasFullAccess else {
            throw ReminderSyncError.notAuthorized
        }

        // Check if modelContext is available
        guard let modelContext else {
            throw ReminderSyncError.modelContextUnavailable
        }

        // Check if sync is configured (prefer identifier, fall back to name for migration)
        guard syncListIdentifier != nil || (syncListName.map { !$0.isEmpty } ?? false) else {
            throw ReminderSyncError.noSyncListConfigured
        }

        // Find the target calendar (Reminders list) - prefer identifier lookup
        let targetCalendar = resolveTargetCalendar()

        guard let targetCalendar else {
            throw ReminderSyncError.listNotFound(syncListName ?? "Unknown")
        }

        // Fetch all reminders from the target list
        let syncData = try await fetchRemindersFromEventKit(in: targetCalendar)

        guard let syncData else {
            return
        }

        // Get all existing reminders from our database that were synced from this calendar
        let existingReminders = try fetchAllReminders()
        // Use uniquingKeysWith to handle potential duplicates from CloudKit sync
        let existingByEKID = [String: Reminder](
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
        let currentEKIDs = Set(syncData.map(\.calendarItemIdentifier))
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

    // MARK: - Sync Helpers

    /// Resolve the target EKCalendar, preferring identifier lookup over name lookup
    func resolveTargetCalendar() -> EKCalendar? {
        if let identifier = syncListIdentifier {
            return findReminderList(byIdentifier: identifier)
        } else if let name = syncListName {
            return findReminderList(named: name)
        }
        return nil
    }

    /// Fetch reminders from EventKit using a Sendable DTO for safe cross-isolation transfer
    func fetchRemindersFromEventKit(in calendar: EKCalendar) async throws -> [ReminderSyncData]? {
        let predicate = eventStore.predicateForReminders(in: [calendar])

        // swiftlint:disable closure_parameter_position
        let ekRemindersData = await withCheckedContinuation {
            (continuation: CheckedContinuation<[ReminderSyncData]?, Never>) in
            // swiftlint:enable closure_parameter_position
            let continuationLock = NSLock()
            var pendingContinuation: CheckedContinuation<[ReminderSyncData]?, Never>? = continuation

            eventStore.fetchReminders(matching: predicate) { reminders in
                var safeData: [ReminderSyncData]?
                if let reminders {
                    var mapped: [ReminderSyncData] = []
                    mapped.reserveCapacity(reminders.count)
                    for reminder in reminders {
                        mapped.append(
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
                        )
                    }
                    safeData = mapped
                }

                continuationLock.lock()
                guard let continuationToResume = pendingContinuation else {
                    continuationLock.unlock()
                    return
                }
                pendingContinuation = nil
                continuationLock.unlock()
                continuationToResume.resume(returning: safeData)
            }
        }

        return ekRemindersData
    }

    // MARK: - CRUD Helpers

    func fetchAllReminders() throws -> [Reminder] {
        guard let modelContext else {
            return []
        }
        let descriptor = FetchDescriptor<Reminder>()
        return try modelContext.fetch(descriptor)
    }

    func createReminder(from data: ReminderSyncData, calendarID: String) -> Reminder {
        Reminder(
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
    }

    func updateReminder(_ reminder: Reminder, from data: ReminderSyncData) {
        reminder.title = data.title
        reminder.notes = data.notes
        reminder.dueDate = data.dueDateComponents?.date
        reminder.isCompleted = data.isCompleted
        reminder.completedAt = data.completionDate
        reminder.updatedAt = data.lastModifiedDate ?? Date()
        reminder.lastSyncedAt = Date()
    }
}
