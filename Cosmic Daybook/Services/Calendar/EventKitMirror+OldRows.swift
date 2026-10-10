import Foundation
import CoreData

// MARK: - Rows from before 2026-10-10
//
// Until 2026-10-10 each device keyed its calendar rows by its own event and
// calendar identifiers, which no other device shares. Those rows are history
// as much as a mirror: EventKit is asked only for a week back and a month
// ahead, so a row outside that window can't be fetched again, and it stays
// exactly as it is. Inside the window, a sync adopts what it can.

extension EventKitMirror {

    /// Gives the old rows inside `fetch`'s window the key of the occurrence
    /// they hold, in place, and files them in `storedByKey` with the rest.
    /// A row matches an occurrence EventKit returned by this device's own
    /// identifier for the event and the same start, or by the same title,
    /// start and end (a copy another device made). Two old copies of one
    /// occurrence both take its key, and the dedup pass folds them
    /// (`mergeSameEventKitEvents`). A row of one of this device's own
    /// calendars that matches nothing is an event since deleted, and goes.
    /// Any other old row is left as it is: outside the window it is history,
    /// and inside it, another device's, to adopt when that device syncs.
    static func adoptOldRows(
        _ rows: [CDCalendarEvent],
        seen: [String: [String: CalendarEventSyncData]],
        from fetch: CalendarFetch,
        into storedByKey: inout [String: [CDCalendarEvent]],
        now: Date
    ) -> Outcome {
        var outcome = Outcome()
        let matcher = OldRowMatcher(seen.values.flatMap(\.values))
        for row in rows where isInsideWindow(row, of: fetch) {
            if let key = matcher.eventKey(for: row), let home = seen[key]?.keys.min() {
                row.eventKitEventID = key
                row.eventKitCalendarID = home
                row.lastSyncedAt = now
                storedByKey[key, default: []].append(row)
                outcome.updated += 1
            } else if let calendarID = row.eventKitCalendarID, fetch.localCalendarIDs.contains(calendarID) {
                row.managedObjectContext?.delete(row)
                outcome.deleted += 1
            }
        }
        return outcome
    }
}

/// Finds the occurrence an old row holds among the ones a sync fetched.
private struct OldRowMatcher {
    /// By this device's identifier for the event: each occurrence's start and key.
    private var byLocalIdentifier: [String: [(start: Date, key: String)]] = [:]
    /// By title, start and end, to the millisecond.
    private var byContent: [String: String] = [:]

    init(_ events: [CalendarEventSyncData]) {
        for event in events {
            if let local = event.localEventIdentifier {
                byLocalIdentifier[local, default: []].append((event.startDate, event.eventKey))
            }
            let content = Self.content(title: event.title, start: event.startDate, end: event.endDate)
            // Two occurrences that read alike: the lower key, as on every device.
            byContent[content] = min(byContent[content] ?? event.eventKey, event.eventKey)
        }
    }

    func eventKey(for row: CDCalendarEvent) -> String? {
        if let local = row.eventKitEventID, let occurrences = byLocalIdentifier[local],
           let match = occurrences.first(where: { EventKitMirror.isSameInstant($0.start, row.startDate) }) {
            return match.key
        }
        guard let start = row.startDate, let end = row.endDate else { return nil }
        return byContent[Self.content(title: row.title, start: start, end: end)]
    }

    private static func content(title: String, start: Date, end: Date) -> String {
        let millis = [start, end].map { String(DataCleanupService.millisecondKey($0) ?? 0) }
        return ([title] + millis).joined(separator: "\u{1F}")
    }
}
