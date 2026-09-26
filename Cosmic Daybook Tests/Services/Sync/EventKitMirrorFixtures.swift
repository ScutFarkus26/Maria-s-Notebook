import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// Values a sync would hand `EventKitMirror`, the rows it leaves, and the
/// copy the mirrors made before 2026-09-25 (every field reassigned and every
/// row stamped on every sync), which the tests compare against.
@MainActor
enum MirrorFixture {

    static let firstSync = Date(timeIntervalSinceReferenceDate: 810_000_000)
    static let secondSync = Date(timeIntervalSinceReferenceDate: 810_000_600)
    static let thirdSync = Date(timeIntervalSinceReferenceDate: 810_001_200)

    /// A due date with its calendar and zone, so `.date` resolves.
    static let dueSoon = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "America/New_York"),
        year: 2026, month: 9, day: 30, hour: 9
    )

    /// The one calendar the tests sync, over the service's window around `firstSync`.
    static let schoolFetch = EventKitMirror.CalendarFetch(
        calendarIDs: ["cal-school"],
        fallbackCalendarID: "cal-school",
        windowStart: firstSync.addingTimeInterval(-7 * 86_400),
        windowEnd: firstSync.addingTimeInterval(30 * 86_400)
    )

    static func event(
        _ id: String,
        title: String = "Assembly",
        day: Int = 0,
        calendar: String? = "cal-school",
        location: String? = "Hall",
        notes: String? = nil,
        allDay: Bool = false
    ) -> CalendarEventSyncData {
        let start = firstSync.addingTimeInterval(TimeInterval(day * 86_400))
        return CalendarEventSyncData(
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            location: location,
            notes: notes,
            isAllDay: allDay,
            eventIdentifier: id,
            calendarIdentifier: calendar
        )
    }

    /// `data` starting `seconds` later.
    static func shifted(_ data: CalendarEventSyncData, by seconds: TimeInterval) -> CalendarEventSyncData {
        CalendarEventSyncData(
            title: data.title,
            startDate: data.startDate.addingTimeInterval(seconds),
            endDate: data.endDate,
            location: data.location,
            notes: data.notes,
            isAllDay: data.isAllDay,
            eventIdentifier: data.eventIdentifier,
            calendarIdentifier: data.calendarIdentifier
        )
    }

    static func reminder(
        _ id: String,
        title: String = "Order paint",
        notes: String? = nil,
        due: DateComponents? = nil,
        completed: Bool = false,
        completedAt: Date? = nil,
        created: Date? = nil,
        modified: Date?
    ) -> ReminderSyncData {
        ReminderSyncData(
            title: title,
            notes: notes,
            dueDateComponents: due,
            isCompleted: completed,
            completionDate: completedAt,
            creationDate: created,
            lastModifiedDate: modified,
            calendarItemIdentifier: id
        )
    }

    static func eventRows(in context: NSManagedObjectContext) -> [String: CDCalendarEvent] {
        let rows = context.safeFetch(CDFetchRequest(CDCalendarEvent.self))
        return Dictionary(
            rows.compactMap { row in row.eventKitEventID.map { ($0, row) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func reminderRows(in context: NSManagedObjectContext) -> [String: CDReminder] {
        let rows = context.safeFetch(CDFetchRequest(CDReminder.self))
        return Dictionary(
            rows.compactMap { row in row.eventKitReminderID.map { ($0, row) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - The copy before 2026-09-25

    /// `CalendarSyncService.updateCDCalendarEvent` as it was: every field
    /// assigned and the row stamped, whether or not anything changed.
    static func legacyUpdate(_ event: CDCalendarEvent, from data: CalendarEventSyncData, now: Date) {
        event.title = data.title
        event.startDate = data.startDate
        event.endDate = data.endDate
        event.location = data.location
        event.notes = data.notes
        event.isAllDay = data.isAllDay
        event.lastSyncedAt = now
    }

    /// `ReminderSyncService.updateCDReminder` as it was.
    static func legacyUpdate(_ reminder: CDReminder, from data: ReminderSyncData, now: Date) {
        reminder.title = data.title
        reminder.notes = data.notes
        reminder.dueDate = data.dueDateComponents?.date
        reminder.isCompleted = data.isCompleted
        reminder.completedAt = data.completionDate
        reminder.updatedAt = data.lastModifiedDate ?? now
        reminder.lastSyncedAt = now
    }

    /// The old sync loops without EventKit or the delete passes: a stored row
    /// EventKit returned was always reassigned, a new one inserted.
    static func legacySync(
        events: [CalendarEventSyncData], reminders: [ReminderSyncData], in context: NSManagedObjectContext, now: Date
    ) {
        let storedEvents = eventRows(in: context)
        for data in events {
            if let row = storedEvents[data.eventIdentifier] {
                legacyUpdate(row, from: data, now: now)
            } else {
                EventKitMirror.insertEvent(data, calendarID: "cal-school", in: context, now: now)
            }
        }
        let storedReminders = reminderRows(in: context)
        for data in reminders {
            if let row = storedReminders[data.calendarItemIdentifier] {
                legacyUpdate(row, from: data, now: now)
            } else {
                EventKitMirror.insertReminder(data, listID: "list", in: context, now: now)
            }
        }
    }
}

/// An on-disk store with persistent history, so a test can see whether a
/// save wrote a transaction at all.
@MainActor
struct HistoryStoreFixture {
    let directory: URL
    let stack: CoreDataStack

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ekmirror-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stack = try CoreDataStack(
            enableCloudKit: false, localStoreURL: directory.appendingPathComponent("mirror.sqlite")
        )
    }

    func historyToken() throws -> NSPersistentHistoryToken {
        let coordinator = stack.container.persistentStoreCoordinator
        let store = try #require(coordinator.persistentStores.first)
        return try #require(coordinator.currentPersistentHistoryToken(fromStores: [store]))
    }

    func transactions(after token: NSPersistentHistoryToken) throws -> [NSPersistentHistoryTransaction] {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        let result = try stack.viewContext.execute(request) as? NSPersistentHistoryResult
        return result?.result as? [NSPersistentHistoryTransaction] ?? []
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
