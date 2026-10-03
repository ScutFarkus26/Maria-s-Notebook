import Foundation
import CoreData

/// Copies EventKit's events and reminders onto the rows that mirror them,
/// `CDCalendarEvent` and `CDReminder`, writing only what changed.
///
/// A sync used to reassign every field of every row EventKit returned and
/// stamp `lastSyncedAt = Date()` on each, so every sync saved every row it
/// saw: one CloudKit export per row, the same again imported on the other
/// device, and a history transaction that kept the backup change gate open
/// all day. Danny decided (2026-09-25) that `lastSyncedAt` is stamped only
/// on a row that is new or changed. Every other value is copied exactly as
/// before, but assigned only when it differs from what the row holds, so a
/// sync over unchanged EventKit data leaves the context without changes and
/// `safeSave()` writes nothing. Dates count as different only when they are
/// a millisecond or more apart (Danny, 2026-09-25; see `isSameInstant`).
enum EventKitMirror {

    /// What one pass did to the stored rows.
    nonisolated struct Outcome: Equatable, Sendable {
        var inserted = 0
        var updated = 0
        var deleted = 0
    }

    // MARK: - Calendar events

    /// The calendars and the window one calendar sync asked EventKit for.
    nonisolated struct CalendarFetch: Sendable {
        /// The calendars that were fetched.
        var calendarIDs: Set<String>
        /// The calendar for a new row whose first occurrence reports none.
        var fallbackCalendarID: String
        var windowStart: Date
        var windowEnd: Date
    }

    /// Mirrors one fetch of events: inserts rows for identifiers not stored
    /// yet, updates stored rows that changed, and deletes stored events of the
    /// fetched calendars inside the fetched window that EventKit no longer has.
    ///
    /// - Parameters:
    ///   - events: what EventKit returned, in its order. A recurring event
    ///     comes back once per occurrence, under one identifier.
    ///   - fetch: the calendars and window `events` came from.
    ///   - now: the stamp for new and changed rows.
    @discardableResult
    static func reconcileEvents(
        _ events: [CalendarEventSyncData], from fetch: CalendarFetch, in context: NSManagedObjectContext, now: Date
    ) -> Outcome {
        let stored = context.safeFetch(CDFetchRequest(CDCalendarEvent.self))
        // Use uniquingKeysWith to handle potential duplicates from CloudKit sync
        let storedByID = [String: CDCalendarEvent](
            stored.compactMap { row in row.eventKitEventID.map { ($0, row) } },
            uniquingKeysWith: { first, _ in first }
        )

        var outcome = Outcome()
        // A stored row used to be assigned every occurrence in turn, so it
        // ended up holding the last one; that is the value to compare with.
        var latest: [String: (row: CDCalendarEvent, data: CalendarEventSyncData)] = [:]
        var firstCalendarIDs: [String: String]?
        for data in events {
            if let row = storedByID[data.eventIdentifier] {
                latest[data.eventIdentifier] = (row, data)
            } else {
                // Still one new row per occurrence, as before: the stored
                // rows were looked up once, before any insert.
                let calendarIDs = firstCalendarIDs ?? firstCalendarIDsByEvent(in: events)
                firstCalendarIDs = calendarIDs
                insertEvent(
                    data,
                    calendarID: calendarIDs[data.eventIdentifier] ?? fetch.fallbackCalendarID,
                    in: context,
                    now: now
                )
                outcome.inserted += 1
            }
        }
        for (row, data) in latest.values {
            outcome.updated += updateEvent(row, from: data, now: now) ? 1 : 0
        }

        // Delete events that no longer exist in EventKit (only for selected calendars).
        // Scope the check to the fetched window: EventKit only returned events
        // overlapping [windowStart, windowEnd], so a stored event outside that window
        // being absent from `currentIDs` means "not fetched", not "deleted".
        // Deleting on absence alone wiped all history older than 7 days on every
        // sync — and the deletes propagated to every device via CloudKit.
        let currentIDs = Set(events.map(\.eventIdentifier))
        for row in stored {
            guard let ekID = row.eventKitEventID,
                  let calendarID = row.eventKitCalendarID,
                  !currentIDs.contains(ekID),
                  fetch.calendarIDs.contains(calendarID),
                  let rowStart = row.startDate,
                  let rowEnd = row.endDate,
                  rowEnd >= fetch.windowStart, rowStart <= fetch.windowEnd
            else { continue }
            context.delete(row)
            outcome.deleted += 1
        }
        return outcome
    }

    /// A new row for `data`, stamped `now`.
    @discardableResult
    static func insertEvent(
        _ data: CalendarEventSyncData, calendarID: String, in context: NSManagedObjectContext, now: Date
    ) -> CDCalendarEvent {
        let event = CDCalendarEvent(context: context)
        event.title = data.title
        event.startDate = data.startDate
        event.endDate = data.endDate
        event.location = data.location
        event.notes = data.notes
        event.isAllDay = data.isAllDay
        event.eventKitEventID = data.eventIdentifier
        event.eventKitCalendarID = calendarID
        event.lastSyncedAt = now
        return event
    }

    /// Copies `data` onto a stored row, assigning only the fields that differ,
    /// and stamps `lastSyncedAt` when any did. Returns whether the row changed.
    @discardableResult
    static func updateEvent(_ event: CDCalendarEvent, from data: CalendarEventSyncData, now: Date) -> Bool {
        var changed = false
        if !isSameText(event.title, data.title) {
            event.title = data.title
            changed = true
        }
        if !isSameInstant(event.startDate, data.startDate) {
            event.startDate = data.startDate
            changed = true
        }
        if !isSameInstant(event.endDate, data.endDate) {
            event.endDate = data.endDate
            changed = true
        }
        if !isSameText(event.location, data.location) {
            event.location = data.location
            changed = true
        }
        if !isSameText(event.notes, data.notes) {
            event.notes = data.notes
            changed = true
        }
        if event.isAllDay != data.isAllDay {
            event.isAllDay = data.isAllDay
            changed = true
        }
        if changed { event.lastSyncedAt = now }
        return changed
    }

    /// Each identifier's calendar as its first occurrence reports it, which
    /// is what a new row took when it searched the fetched events in order.
    private static func firstCalendarIDsByEvent(in events: [CalendarEventSyncData]) -> [String: String] {
        var seen: Set<String> = []
        var calendarIDs: [String: String] = [:]
        for event in events where seen.insert(event.eventIdentifier).inserted {
            calendarIDs[event.eventIdentifier] = event.calendarIdentifier
        }
        return calendarIDs
    }

    // MARK: - Reminders

    /// Mirrors one fetch of a Reminders list: inserts rows for identifiers not
    /// stored yet, updates stored rows that changed, and deletes stored rows of
    /// this list that EventKit no longer returns.
    @discardableResult
    static func reconcileReminders(
        _ reminders: [ReminderSyncData], listID: String, in context: NSManagedObjectContext, now: Date
    ) -> Outcome {
        let stored = context.safeFetch(CDFetchRequest(CDReminder.self))
        // Use uniquingKeysWith to handle potential duplicates from CloudKit sync
        let storedByID = [String: CDReminder](
            stored.compactMap { row in row.eventKitReminderID.map { ($0, row) } },
            uniquingKeysWith: { first, _ in first }
        )

        var outcome = Outcome()
        // An identifier EventKit repeats updated the same row each time, so
        // the last entry is the one the row ended up holding.
        var latest: [String: (row: CDReminder, data: ReminderSyncData)] = [:]
        for data in reminders {
            if let row = storedByID[data.calendarItemIdentifier] {
                latest[data.calendarItemIdentifier] = (row, data)
            } else {
                insertReminder(data, listID: listID, in: context, now: now)
                outcome.inserted += 1
            }
        }
        for (row, data) in latest.values {
            outcome.updated += updateReminder(row, from: data, now: now) ? 1 : 0
        }

        // Delete reminders that no longer exist in EventKit (orphan cleanup)
        let currentIDs = Set(reminders.map(\.calendarItemIdentifier))
        for row in stored {
            if let ekID = row.eventKitReminderID,
               !currentIDs.contains(ekID),
               row.eventKitCalendarID == listID {
                context.delete(row)
                outcome.deleted += 1
            }
        }
        return outcome
    }

    /// A new row for `data`, stamped `now`.
    @discardableResult
    static func insertReminder(
        _ data: ReminderSyncData, listID: String, in context: NSManagedObjectContext, now: Date
    ) -> CDReminder {
        let reminder = CDReminder(context: context)
        reminder.title = data.title
        reminder.notes = data.notes
        reminder.dueDate = data.dueDateComponents?.date
        reminder.isCompleted = data.isCompleted
        reminder.completedAt = data.completionDate
        reminder.createdAt = data.creationDate ?? now
        reminder.updatedAt = data.lastModifiedDate ?? now
        reminder.eventKitReminderID = data.calendarItemIdentifier
        reminder.eventKitCalendarID = listID
        reminder.lastSyncedAt = now
        return reminder
    }

    /// Copies `data` onto a stored row, assigning only the fields that differ,
    /// and stamps `lastSyncedAt` when any did. Returns whether the row changed.
    ///
    /// A reminder EventKit reports no modification date for keeps the old
    /// rule, `updatedAt` = the sync time, so that row is still rewritten on
    /// every sync.
    @discardableResult
    static func updateReminder(_ reminder: CDReminder, from data: ReminderSyncData, now: Date) -> Bool {
        var changed = false
        if !isSameText(reminder.title, data.title) {
            reminder.title = data.title
            changed = true
        }
        if !isSameText(reminder.notes, data.notes) {
            reminder.notes = data.notes
            changed = true
        }
        let dueDate = data.dueDateComponents?.date
        if !isSameInstant(reminder.dueDate, dueDate) {
            reminder.dueDate = dueDate
            changed = true
        }
        if reminder.isCompleted != data.isCompleted {
            reminder.isCompleted = data.isCompleted
            changed = true
        }
        if !isSameInstant(reminder.completedAt, data.completionDate) {
            reminder.completedAt = data.completionDate
            changed = true
        }
        let updatedAt = data.lastModifiedDate ?? now
        if !isSameInstant(reminder.updatedAt, updatedAt) {
            reminder.updatedAt = updatedAt
            changed = true
        }
        if changed { reminder.lastSyncedAt = now }
        return changed
    }

    // MARK: - Comparison

    /// Whether a stored date already holds `incoming`, to the millisecond
    /// (Danny, 2026-09-25). CloudKit keeps dates in milliseconds, so a row
    /// another device wrote comes back with EventKit's sub-millisecond digits
    /// cut off; comparing exactly would rewrite (and re-upload) it on every
    /// sync, and with both devices syncing one list they would rewrite each
    /// other's rows indefinitely. Dates less than a millisecond apart count as
    /// the same, and the stored value is left as it is.
    static func isSameInstant(_ stored: Date?, _ incoming: Date?) -> Bool {
        switch (stored, incoming) {
        case (nil, nil):
            return true
        case let (stored?, incoming?):
            return abs(stored.timeIntervalSince(incoming)) < 0.001
        default:
            return false
        }
    }

    /// Whether a stored text field already holds `incoming`, code unit for
    /// code unit. Swift's `==` calls canonically equivalent strings equal (a
    /// precomposed "é" and "e" plus a combining accent), but the row stores
    /// the exact form EventKit returned, which is what the old copy wrote.
    static func isSameText(_ stored: String?, _ incoming: String?) -> Bool {
        switch (stored, incoming) {
        case (nil, nil):
            return true
        case let (stored?, incoming?):
            return stored.utf16.elementsEqual(incoming.utf16)
        default:
            return false
        }
    }
}
