#if canImport(Testing)
import Foundation
@testable import Maria_s_Notebook

/// Test helper utilities for creating dates in tests
enum TestCalendar {
    /// Creates a date with specified components at noon (12:00:00) to avoid timezone issues
    static func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components)!
    }

    /// Creates a date at start of day (00:00:00) using AppCalendar
    static func startOfDay(year: Int, month: Int, day: Int) -> Date {
        let d = date(year: year, month: month, day: day)
        return AppCalendar.startOfDay(d)
    }

    /// Creates an array of dates representing school days (excluding weekends)
    /// from a start date to an end date (inclusive)
    static func schoolDays(from start: Date, to end: Date) -> [Date] {
        var days: [Date] = []
        var cursor = AppCalendar.startOfDay(start)
        let endDay = AppCalendar.startOfDay(end)

        while cursor <= endDay {
            let weekday = AppCalendar.shared.component(.weekday, from: cursor)
            // Exclude weekends (Sunday=1, Saturday=7)
            if weekday != 1 && weekday != 7 {
                days.append(cursor)
            }
            cursor = AppCalendar.addingDays(1, to: cursor)
            if days.count > 1000 { break } // Safety limit
        }

        return days
    }

    /// Counts school days between two dates (excluding weekends, inclusive of start and end if they're school days)
    static func schoolDayCount(from start: Date, to end: Date) -> Int {
        return schoolDays(from: start, to: end).count
    }
}

#endif
