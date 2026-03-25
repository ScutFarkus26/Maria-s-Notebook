import Foundation

/// Centralized DateFormatter instances for consistent date formatting across the app.
/// Each formatter is created once and reused.
enum DateFormatters {
    /// Medium date, short time with relative formatting (e.g., "Today, 3:45 PM")
    static let mediumDateTimeRelative: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    /// Medium date, short time without relative formatting (e.g., "Jan 15, 2024, 3:45 PM")
    static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Month and year only (e.g., "January 2024")
    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    /// ISO 8601 date format (e.g., "2024-01-15")
    static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Medium date only, no time (e.g., "Jan 15, 2024")
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Weekday plus short month/day (e.g., "Monday, Jan 15")
    static let weekdayAndDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return formatter
    }()

    /// Short month and day (e.g., "Jan 15")
    static let shortMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    /// Short date only (e.g., "1/15/24")
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    /// Short time only (e.g., "3:45 PM")
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Long date only, no time (e.g., "January 15, 2024")
    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    /// Full date only, no time (e.g., "Monday, January 15, 2024")
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    /// Standalone month and year, locale-sensitive (e.g., "January 2024")
    static let localizedMonthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter
    }()

    /// Full weekday name (e.g., "Monday")
    static let weekdayFull: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    /// Abbreviated weekday name (e.g., "Mon")
    static let weekdayAbbrev: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    /// Short date and short time (e.g., "1/15/24, 3:45 PM")
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    /// ISO 8601 full datetime with timezone (e.g., "2024-01-15T15:45:00Z")
    /// Returns a fresh formatter because ISO8601DateFormatter is not Sendable.
    static var iso8601DateTime: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        return formatter
    }

    /// Day-of-month number only, locale-sensitive (e.g., "15")
    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()

    /// Short month, day, and year, locale-sensitive (e.g., "Mar 13, 2026")
    static let shortMonthDayYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter
    }()

    /// Local ISO date string for internal keys, e.g. "2024-01-15" in the device timezone
    static let isoDateLocal: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Backup filename timestamp (e.g., "2024-01-15_14-30-00")
    static let backupFilename: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
