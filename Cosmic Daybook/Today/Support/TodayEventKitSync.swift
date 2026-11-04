// TodayEventKitSync.swift
// Today's EventKit work: the Calendar sync it runs on appear and on
// activation. (The Reminders sync and its write-back retired 2026-11-03.)

import CoreData
import Foundation
import OSLog

nonisolated private let logger = Logger.sync

/// What Today asks of the EventKit sync service, kept out of the view so
/// its rules can be tested without touching EventKit.
///
/// None of it runs in the Sample Class (bug hunt 2026-10-17, #30). The
/// service holds My Class's store and the real Calendar: a sync there copied
/// it into the practice store, and its time skipped My Class's next sync
/// for 10 minutes.
@MainActor
struct TodayEventKitSync {
    /// Today is showing the Sample Class: nothing here runs.
    let isSampleClassroom: Bool

    private let calendar: @MainActor () async -> Void

    /// The live work, through the graph's service.
    init(dependencies: AppDependencies) {
        self.init(
            isSampleClassroom: dependencies.isSampleClassroom,
            calendar: { await Self.syncCalendar(dependencies.calendarSync) }
        )
    }

    /// Tests pass their own work in place of EventKit's.
    init(isSampleClassroom: Bool, calendar: @escaping @MainActor () async -> Void) {
        self.isSampleClassroom = isSampleClassroom
        self.calendar = calendar
    }

    /// Copies the chosen calendars' events into the notebook.
    func syncCalendarEvents() async {
        guard !isSampleClassroom else { return }
        await calendar()
    }

    // MARK: - Live work

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
