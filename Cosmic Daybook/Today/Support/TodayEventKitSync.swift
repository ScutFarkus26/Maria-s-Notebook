// TodayEventKitSync.swift
// Today's two-way EventKit work: the Reminders and Calendar syncs it runs on
// appear and on activation, and a reminder tick written back to Reminders.

import CoreData
import Foundation
import OSLog

nonisolated private let logger = Logger.sync

/// What Today asks of the EventKit sync services, kept out of the view so
/// its rules can be tested without touching EventKit.
///
/// None of it runs in the Sample Class (bug hunt 2026-10-17, #30). The
/// services hold My Class's store and the real Reminders and Calendar: a
/// sync there copied them into the practice store (and its time skipped My
/// Class's next sync for 10 minutes), and a tick there ticked the real
/// reminder, which My Class then marked done.
@MainActor
struct TodayEventKitSync {
    /// Today is showing the Sample Class: nothing here runs.
    let isSampleClassroom: Bool

    private let reminders: @MainActor () async -> Void
    private let calendar: @MainActor () async -> Void
    private let writeBack: @MainActor (CDReminder) async -> Void

    /// The live work, through the graph's services.
    init(dependencies: AppDependencies) {
        self.init(
            isSampleClassroom: dependencies.isSampleClassroom,
            reminders: { await Self.syncReminders(dependencies.reminderSync) },
            calendar: { await Self.syncCalendar(dependencies.calendarSync) },
            writeBack: { reminder in
                do {
                    try await dependencies.reminderSync.updateReminderCompletionInEventKit(reminder)
                } catch {
                    logger.warning("Failed to update reminder in EventKit: \(error)")
                }
            }
        )
    }

    /// Tests pass their own work in place of EventKit's.
    init(
        isSampleClassroom: Bool,
        reminders: @escaping @MainActor () async -> Void,
        calendar: @escaping @MainActor () async -> Void,
        writeBack: @escaping @MainActor (CDReminder) async -> Void
    ) {
        self.isSampleClassroom = isSampleClassroom
        self.reminders = reminders
        self.calendar = calendar
        self.writeBack = writeBack
    }

    /// Copies the chosen Reminders list into the notebook.
    func syncReminders() async {
        guard !isSampleClassroom else { return }
        await reminders()
    }

    /// Copies the chosen calendars' events into the notebook.
    func syncCalendarEvents() async {
        guard !isSampleClassroom else { return }
        await calendar()
    }

    /// Ticks or unticks `reminder` in Apple Reminders after Today saved the change.
    func writeBackCompletion(of reminder: CDReminder) async {
        guard !isSampleClassroom else { return }
        await writeBack(reminder)
    }

    // MARK: - Live work

    private static func syncReminders(_ service: ReminderSyncService) async {
        guard service.syncListIdentifier != nil || service.syncListName != nil else { return }
        do {
            try await service.syncReminders()
        } catch let error as ReminderSyncError where error.isConfigurationIssue {
            #if DEBUG
            logger.notice("Reminder sync skipped: \(error.localizedDescription)")
            #endif
        } catch {
            #if DEBUG
            logger.error("Reminder sync failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func syncCalendar(_ service: CalendarSyncService) async {
        guard !service.syncCalendarIdentifiers.isEmpty else { return }
        do {
            try await service.syncEvents()
        } catch {
            #if DEBUG
            logger.error("Calendar sync failed: \(error.localizedDescription)")
            #endif
        }
    }
}
