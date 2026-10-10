import EventKit
import Foundation

// The keys `EventKitMirror` files EventKit's occurrences and calendars under,
// read off EventKit's objects.
extension CalendarSyncService {

    /// One occurrence as the mirror keeps it, keyed the same way on every
    /// device: by the server's identifier for the event (the device's own
    /// for a calendar on this device only, which EventKit passes through)
    /// and the occurrence's original date, on its calendar's account and
    /// title. This device's own identifier comes along for matching rows
    /// from before 2026-10-10.
    static func syncData(for event: EKEvent) -> CalendarEventSyncData {
        let external = event.calendarItemExternalIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            ?? event.calendarItemIdentifier
        return CalendarEventSyncData(
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            location: event.location,
            notes: event.notes,
            isAllDay: event.isAllDay,
            eventKey: EventKitMirror.eventKey(
                externalIdentifier: external,
                occurrenceDate: event.occurrenceDate ?? event.startDate,
                isAllDay: event.isAllDay
            ),
            calendarKey: event.calendar.map(Self.calendarKey(for:)),
            localEventIdentifier: event.eventIdentifier
        )
    }

    /// `calendar`'s key, the same on every device that has it.
    static func calendarKey(for calendar: EKCalendar) -> String {
        EventKitMirror.calendarKey(
            sourceTitle: calendar.source?.title ?? "",
            calendarTitle: calendar.title,
            isExchange: calendar.source?.sourceType == .exchange
        )
    }
}
