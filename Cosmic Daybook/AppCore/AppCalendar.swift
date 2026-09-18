import Foundation

/// Canonical calendar utilities for day-boundary normalization across the app.
/// Use these helpers instead of `Calendar.current` directly to avoid mismatches
/// between Planning, Today, and Agenda screens.
nonisolated enum AppCalendar {
    /// Shared calendar used for all date normalization: Gregorian in the device
    /// time zone. The time zone is `autoupdatingCurrent`, so the value never has
    /// to be mutated to follow a device time-zone change — which is what lets it
    /// be an immutable, `Sendable` `let` that nonisolated model initializers and
    /// background actors can read without a lock.
    ///
    /// Note: unlike `Calendar.current`, this calendar carries no locale, so use
    /// `Calendar.current` (or a `DateFormatter`) for locale symbols such as
    /// `shortMonthSymbols`; `firstWeekday` and day arithmetic are identical.
    static let shared: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .autoupdatingCurrent
        return cal
    }()

    // MARK: - Canonical helpers

    /// Returns the start of day in the device time zone for the given date.
    nonisolated static func startOfDay(_ date: Date) -> Date {
        shared.startOfDay(for: date)
    }

    /// Returns the half-open range [startOfDay(date), startOfDay(date)+1day)
    /// used for all day-bound queries.
    nonisolated static func dayRange(for date: Date) -> (start: Date, end: Date) {
        let start = startOfDay(date)
        let end = shared.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    /// True if two dates are in the same day (device time zone).
    nonisolated static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        shared.isDate(a, inSameDayAs: b)
    }

    /// Adds whole days to a date using the shared calendar.
    nonisolated static func addingDays(_ days: Int, to date: Date) -> Date {
        shared.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// A short weekday label (e.g., "Mon", "Tue").
    nonisolated static func weekdayLabel(for date: Date) -> String {
        date.formatted(Date.FormatStyle().weekday(.abbreviated))
    }

    /// Stable identifier for a day bucket (start-of-day epoch seconds).
    /// Useful for `id:` values in `ForEach` when you want day-identity rather than full timestamps.
    nonisolated static func dayID(_ day: Date) -> String {
        let start = startOfDay(day)
        return "day_\(Int(start.timeIntervalSince1970))"
    }
}
