import Foundation

/// Canonical calendar utilities for day-boundary normalization across the app.
/// Use these helpers instead of `Calendar.current` directly to avoid mismatches
/// between Planning, Today, and Agenda screens.
enum AppCalendar {
    /// Shared calendar used for all date normalization.
    /// Defaults to Gregorian with the current time zone.
    static var shared: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    /// Update the shared calendar's time zone to match the provided calendar.
    /// Call this whenever the environment calendar/timezone changes.
    static func adopt(timeZoneFrom calendar: Calendar) {
        var cal = shared
        cal.timeZone = calendar.timeZone
        shared = cal
    }

    // MARK: - Canonical helpers

    /// Returns the start of day in the device time zone for the given date.
    static func startOfDay(_ date: Date) -> Date {
        shared.startOfDay(for: date)
    }

    /// Returns the half-open range [startOfDay(date), startOfDay(date)+1day)
    /// used for all day-bound queries.
    static func dayRange(for date: Date) -> (start: Date, end: Date) {
        let start = startOfDay(date)
        let end = shared.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    /// True if two dates are in the same day (device time zone).
    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        shared.isDate(a, inSameDayAs: b)
    }

    /// Adds whole days to a date using the shared calendar.
    static func addingDays(_ days: Int, to date: Date) -> Date {
        shared.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// A short weekday label (e.g., "Mon", "Tue").
    static func weekdayLabel(for date: Date) -> String {
        date.formatted(Date.FormatStyle().weekday(.abbreviated))
    }
}
