import Foundation

/// Helper functions for common date calculation patterns.
/// Reduces duplication and ensures consistent date arithmetic.
enum DateCalculations {
    /// Safely adds a time component to a date using a calendar.
    /// - Parameters:
    ///   - date: The base date
    ///   - component: The calendar component to add
    ///   - value: The value to add
    ///   - calendar: The calendar to use (default: AppCalendar.shared)
    /// - Returns: The new date, or the original date if calculation fails
    static func adding(
        _ component: Calendar.Component,
        value: Int,
        to date: Date,
        calendar: Calendar = AppCalendar.shared
    ) -> Date {
        calendar.date(byAdding: component, value: value, to: date) ?? date
    }
    
    /// Safely adds days to a date.
    /// - Parameters:
    ///   - days: The number of days to add (can be negative)
    ///   - date: The base date
    ///   - calendar: The calendar to use (default: AppCalendar.shared)
    /// - Returns: The new date, or the original date if calculation fails
    static func addingDays(
        _ days: Int,
        to date: Date,
        calendar: Calendar = AppCalendar.shared
    ) -> Date {
        adding(.day, value: days, to: date, calendar: calendar)
    }
    
    /// Safely adds hours to a date.
    /// - Parameters:
    ///   - hours: The number of hours to add (can be negative)
    ///   - date: The base date
    ///   - calendar: The calendar to use (default: AppCalendar.shared)
    /// - Returns: The new date, or the original date if calculation fails
    static func addingHours(
        _ hours: Int,
        to date: Date,
        calendar: Calendar = AppCalendar.shared
    ) -> Date {
        adding(.hour, value: hours, to: date, calendar: calendar)
    }
    
    /// Gets the start of day for a date using a calendar.
    /// - Parameters:
    ///   - date: The date
    ///   - calendar: The calendar to use (default: AppCalendar.shared)
    /// - Returns: The start of day
    static func startOfDay(
        _ date: Date,
        calendar: Calendar = AppCalendar.shared
    ) -> Date {
        calendar.startOfDay(for: date)
    }
}



