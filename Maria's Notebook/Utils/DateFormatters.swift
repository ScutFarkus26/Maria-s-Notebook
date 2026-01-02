import Foundation

/// Centralized DateFormatter instances for consistent date formatting across the app.
/// All formatters are thread-safe and can be reused.
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
}


