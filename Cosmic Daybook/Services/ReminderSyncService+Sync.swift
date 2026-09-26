import Foundation
import CoreData
import OSLog
import EventKit

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

        // Check if managedObjectContext is available
        guard let context = managedObjectContext else {
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

        // Insert new reminders, rewrite only the rows whose values changed
        // (re-uncompleted reminders included), and delete the ones gone from
        // the list. An unchanged list leaves the context clean, so the save
        // below writes nothing.
        EventKitMirror.reconcileReminders(
            syncData, listID: targetCalendar.calendarIdentifier, in: context, now: Date()
        )

        context.safeSave()

        // Update last sync time after successful sync
        lastSyncTime = Date()
    }

    // MARK: - Sync Helpers

    /// Resolve the target EKCalendar, preferring identifier lookup over name lookup.
    /// A stale identifier (list deleted and recreated, or config restored on another
    /// device) falls back to the stored display name; a successful name lookup
    /// backfills the identifier so future lookups resolve directly.
    func resolveTargetCalendar() -> EKCalendar? {
        if let identifier = syncListIdentifier,
           let calendar = findReminderList(byIdentifier: identifier) {
            return calendar
        }
        if let name = syncListName, let calendar = findReminderList(named: name) {
            if syncListIdentifier != calendar.calendarIdentifier {
                syncListIdentifier = calendar.calendarIdentifier
            }
            return calendar
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

}
