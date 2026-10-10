import Foundation
import CoreData

/// Sendable DTO carrying one EventKit occurrence out of `EKEvent` into the mirror.
nonisolated struct CalendarEventSyncData: Sendable, Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?
    let isAllDay: Bool
    /// The occurrence, the same on every device (`EventKitMirror.eventKey`).
    let eventKey: String
    /// The occurrence's calendar, the same on every device
    /// (`EventKitMirror.calendarKey`); nil when EventKit reports none.
    let calendarKey: String?
    /// This device's own identifier for the event (`eventIdentifier`): what a
    /// row from before 2026-10-10 was keyed by, so it can be matched.
    var localEventIdentifier: String?
}

extension EventKitMirror {

    // MARK: - Calendar events
    //
    // Rows are keyed the same way on every device (2026-10-10; Apple's notes
    // on `calendarItemExternalIdentifier`), so a Mac and an iPad syncing one
    // calendar update the same rows instead of each adding its own, and each
    // occurrence of a repeating event keeps its own row:
    //
    // - `eventKitEventID` is `x:<external identifier>|<occurrence>`: the
    //   server's identifier, the same on every device and for every
    //   occurrence of a series, plus the occurrence's original date (its day,
    //   for an all-day event, which EventKit reports in the device's zone).
    // - `eventKitCalendarID` is `c:<account>|<calendar>`, the calendar's
    //   account and title, since a calendar's identifier is local. Exchange
    //   gives one event different identifiers on iOS and on the Mac, so an
    //   Exchange calendar's key also names the platform: those events can show
    //   twice, but neither platform deletes the other's rows.
    //
    // A device moves or deletes only rows of calendars it syncs itself (or
    // synced under a name it has since changed). A row under a calendar this
    // device has but doesn't sync is another device's choice, and is left
    // alone. A row under a calendar this device doesn't have by that key
    // (the same calendar under another account name on another device, as
    // Google's can be) is kept up to date on its own calendar, and deleted
    // only when this device still sees other occurrences of that event in a
    // calendar it syncs, so two devices never trade deletes. Rows from before
    // the change hold one device's local identifiers: see `adoptOldRows`.

    /// The calendars and the window one calendar sync asked EventKit for.
    nonisolated struct CalendarFetch: Sendable {
        /// The keys (`calendarKey`) of the calendars this device syncs.
        var calendarKeys: Set<String>
        /// The keys those calendars had before they were renamed.
        var formerCalendarKeys: Set<String> = []
        /// The keys of the calendars this device has but doesn't sync.
        var unsyncedCalendarKeys: Set<String> = []
        /// This device's own identifiers for the calendars it syncs: how a
        /// row from before 2026-10-10 named its calendar.
        var localCalendarIDs: Set<String> = []
        /// The calendar for an occurrence EventKit reports none for.
        var fallbackCalendarKey: String
        var windowStart: Date
        var windowEnd: Date

        /// The calendars whose rows this device may move and delete.
        var ownedCalendarKeys: Set<String> { calendarKeys.union(formerCalendarKeys) }
    }

    /// Marks a row keyed the cross-device way.
    static let eventKeyPrefix = "x:"
    /// Marks a cross-device calendar key.
    static let calendarKeyPrefix = "c:"

    /// One occurrence of one event, the same on every device that sees it:
    /// `x:<external identifier>|<occurrence>`. A timed occurrence is its
    /// original start in UTC, to the second; an all-day one is its day, read
    /// in `timeZone`, since EventKit reports floating dates in the device's
    /// zone.
    static func eventKey(
        externalIdentifier: String, occurrenceDate: Date, isAllDay: Bool, timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = isAllDay ? timeZone : .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: occurrenceDate)
        func digits(_ value: Int?, _ width: Int) -> String {
            let text = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        var occurrence = digits(parts.year, 4) + "-" + digits(parts.month, 2) + "-" + digits(parts.day, 2)
        if !isAllDay {
            let time = [parts.hour, parts.minute, parts.second].map { digits($0, 2) }.joined(separator: ":")
            occurrence += "T" + time + "Z"
        }
        return eventKeyPrefix + externalIdentifier + "|" + occurrence
    }

    /// A calendar, the same on every device: `c:<account>|<calendar>`, and
    /// `|<platform>` after it for an Exchange calendar (see above).
    static func calendarKey(
        sourceTitle: String, calendarTitle: String, isExchange: Bool, platform: String = currentPlatform
    ) -> String {
        let key = calendarKeyPrefix + sourceTitle + "|" + calendarTitle
        return isExchange ? key + "|" + platform : key
    }

    /// The platform an Exchange calendar's key names.
    static var currentPlatform: String {
        #if os(macOS)
        "macOS"
        #else
        "iOS"
        #endif
    }

    /// Mirrors one fetch of events: inserts a row for each occurrence not
    /// stored yet, updates stored rows that changed, deletes rows of this
    /// device's calendars inside the fetched window that EventKit no longer
    /// has, and re-keys rows in the old format that it can match.
    ///
    /// - Parameters:
    ///   - events: what EventKit returned. A recurring event comes back once
    ///     per occurrence, each under its own `eventKey`.
    ///   - fetch: the calendars and window `events` came from.
    ///   - now: the stamp for new and changed rows.
    @discardableResult
    static func reconcileEvents(
        _ events: [CalendarEventSyncData], from fetch: CalendarFetch, in context: NSManagedObjectContext, now: Date
    ) -> Outcome {
        var storedByKey: [String: [CDCalendarEvent]] = [:]
        var oldRows: [CDCalendarEvent] = []
        for row in context.safeFetch(CDFetchRequest(CDCalendarEvent.self)) {
            guard let key = row.eventKitEventID, key.hasPrefix(eventKeyPrefix) else {
                oldRows.append(row)
                continue
            }
            // Two devices can each insert an occurrence before either sees the
            // other's. Both rows are kept current until the dedup pass folds
            // them (`mergeSameEventKitEvents`).
            storedByKey[key, default: []].append(row)
        }

        let seen = occurrencesByEvent(events, fallbackCalendarKey: fetch.fallbackCalendarKey)
        var outcome = adoptOldRows(oldRows, seen: seen, from: fetch, into: &storedByKey, now: now)
        for (key, byCalendar) in seen {
            // An event in several of this device's calendars (an invitation to
            // a shared calendar's event, say) is one row, filed under the
            // first of them by key, so every device files it the same way.
            guard let home = byCalendar.keys.min(), let homeData = byCalendar[home] else { continue }
            guard let rows = storedByKey[key] else {
                insertEvent(homeData, calendarID: home, in: context, now: now)
                outcome.inserted += 1
                continue
            }
            for row in rows {
                let changed = refresh(row, from: byCalendar, home: home, fetch: fetch, now: now)
                outcome.updated += changed ? 1 : 0
            }
        }
        let gone = storedByKey.filter { seen[$0.key] == nil }.values.joined()
        let seenEvents = Set(seen.keys.compactMap(externalIdentifier(ofEventKey:)))
        outcome.deleted += deleteGone(gone, from: fetch, seenEvents: seenEvents, in: context)
        return outcome
    }

    /// Deletes every row of the given calendars, whatever its dates: what a
    /// device does once when it stops syncing a calendar. Returns how many
    /// rows went. Does not save.
    @discardableResult
    static func removeEvents(inCalendars calendarKeys: Set<String>, in context: NSManagedObjectContext) -> Int {
        guard !calendarKeys.isEmpty else { return 0 }
        let request = CDFetchRequest(CDCalendarEvent.self)
        request.predicate = NSPredicate(format: "eventKitCalendarID IN %@", Array(calendarKeys))
        let rows = context.safeFetch(request)
        rows.forEach(context.delete)
        return rows.count
    }

    /// A new row for `data` on the calendar `calendarID` (a `calendarKey`),
    /// stamped `now`.
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
        event.eventKitEventID = data.eventKey
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

    /// Brings one stored row of a fetched event up to date. A row under one
    /// of the calendars the event was fetched from takes that calendar's copy.
    /// A row under a calendar this device syncs (or synced before a rename)
    /// that no longer has the event follows it to `home`. A row under a
    /// calendar this device has but doesn't sync is another device's choice
    /// and is left as it is. A row under a calendar this device doesn't have
    /// by that key takes `home`'s copy but keeps its calendar: it is most
    /// likely the same calendar, named under another account title on the
    /// device that filed it. Returns whether the row changed.
    private static func refresh(
        _ row: CDCalendarEvent,
        from byCalendar: [String: CalendarEventSyncData],
        home: String,
        fetch: CalendarFetch,
        now: Date
    ) -> Bool {
        let rowCalendar = row.eventKitCalendarID ?? ""
        if let data = byCalendar[rowCalendar] {
            return updateEvent(row, from: data, now: now)
        }
        guard let data = byCalendar[home], !fetch.unsyncedCalendarKeys.contains(rowCalendar) else { return false }
        guard fetch.ownedCalendarKeys.contains(rowCalendar) else {
            return updateEvent(row, from: data, now: now)
        }
        updateEvent(row, from: data, now: now)
        row.eventKitCalendarID = home
        row.lastSyncedAt = now
        return true
    }

    /// Deletes the rows of occurrences a fetch no longer returned, only
    /// inside the fetched window: EventKit returned only events overlapping
    /// it, so a stored event outside it is "not fetched", not "deleted".
    /// Deleting on absence alone once wiped all history older than 7 days on
    /// every sync, and the deletes reached every device. A row goes when its
    /// calendar is one this device syncs, or when it is under a calendar this
    /// device doesn't have by that key and the device still sees other
    /// occurrences of the same event (`seenEvents`, external identifiers) in
    /// the calendars it syncs: then this occurrence is known to be gone, not
    /// just out of sight. Returns how many rows went.
    private static func deleteGone(
        _ rows: some Sequence<CDCalendarEvent>,
        from fetch: CalendarFetch,
        seenEvents: Set<String>,
        in context: NSManagedObjectContext
    ) -> Int {
        let owned = fetch.ownedCalendarKeys
        var deleted = 0
        for row in rows where isInsideWindow(row, of: fetch) {
            let calendarKey = row.eventKitCalendarID ?? ""
            let event = row.eventKitEventID.flatMap(externalIdentifier(ofEventKey:))
            let isKnownGone = !fetch.unsyncedCalendarKeys.contains(calendarKey)
                && event.map(seenEvents.contains) == true
            guard owned.contains(calendarKey) || isKnownGone else { continue }
            context.delete(row)
            deleted += 1
        }
        return deleted
    }

    /// Whether `row`'s dates overlap the window `fetch` asked EventKit for.
    static func isInsideWindow(_ row: CDCalendarEvent, of fetch: CalendarFetch) -> Bool {
        guard let start = row.startDate, let end = row.endDate else { return false }
        return end >= fetch.windowStart && start <= fetch.windowEnd
    }

    /// The external identifier in an `eventKey`, or nil for a key in another
    /// format.
    static func externalIdentifier(ofEventKey key: String) -> String? {
        guard key.hasPrefix(eventKeyPrefix), let bar = key.lastIndex(of: "|") else { return nil }
        let start = key.index(key.startIndex, offsetBy: eventKeyPrefix.count)
        return start <= bar ? String(key[start..<bar]) : nil
    }

    /// Each fetched event's occurrences by calendar. An event in two
    /// calendars comes back once for each, under one key. Two copies in one
    /// calendar (an ICS file imported twice) keep the one that sorts first,
    /// so every device keeps the same copy.
    private static func occurrencesByEvent(
        _ events: [CalendarEventSyncData], fallbackCalendarKey: String
    ) -> [String: [String: CalendarEventSyncData]] {
        var seen: [String: [String: CalendarEventSyncData]] = [:]
        for event in events {
            let calendarKey = event.calendarKey ?? fallbackCalendarKey
            if let kept = seen[event.eventKey]?[calendarKey], !sortsFirst(event, kept) { continue }
            seen[event.eventKey, default: [:]][calendarKey] = event
        }
        return seen
    }

    /// An order on copies of one occurrence that every device computes alike.
    private static func sortsFirst(_ lhs: CalendarEventSyncData, _ rhs: CalendarEventSyncData) -> Bool {
        let lhsText = [lhs.title, lhs.location ?? "", lhs.notes ?? ""]
        let rhsText = [rhs.title, rhs.location ?? "", rhs.notes ?? ""]
        if lhsText != rhsText { return lhsText.lexicographicallyPrecedes(rhsText) }
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        return lhs.endDate < rhs.endDate
    }
}
