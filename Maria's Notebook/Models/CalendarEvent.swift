import Foundation
import SwiftData

/// A calendar event model that syncs with Apple's Calendar app via EventKit.
/// Calendar events are displayed in the Today view and can be synced from a specific iCloud calendar.
@Model
final class CalendarEvent: Identifiable {
    /// Unique identifier for this event
    var id: UUID = UUID()

    /// The title of the event
    var title: String = ""

    /// The start date/time of the event
    var startDate: Date = Date()

    /// The end date/time of the event
    var endDate: Date = Date()

    /// Optional location for the event
    var location: String?

    /// Optional notes for the event
    var notes: String?

    /// Whether this is an all-day event
    var isAllDay: Bool = false

    /// The EventKit event identifier for syncing
    /// This allows us to track which Apple Calendar event this corresponds to
    var eventKitEventID: String?

    /// The calendar identifier in EventKit that this event belongs to
    var eventKitCalendarID: String?

    /// When this event was last synced from EventKit
    var lastSyncedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        notes: String? = nil,
        isAllDay: Bool = false,
        eventKitEventID: String? = nil,
        eventKitCalendarID: String? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.isAllDay = isAllDay
        self.eventKitEventID = eventKitEventID
        self.eventKitCalendarID = eventKitCalendarID
        self.lastSyncedAt = lastSyncedAt
    }
}
