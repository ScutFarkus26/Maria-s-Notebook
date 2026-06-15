// SchoolYear.swift
// Value types + pure boundary math for the school-year "viewing lens".
//
// A school year is a half-open date interval [start, end). Boundaries come from a
// configurable start month/day (default Sept 1, matching FloridaGradeCalculator). All math
// here is pure and `nonisolated` so it is trivially unit-testable and callable from any
// context. The observable state + persistence lives in `SchoolYearStore`.

import Foundation

/// A half-open date range `[start, end)`.
struct DateRange: Equatable, Sendable {
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

/// A single school year, e.g. 2025–2026, as `[start, end)`.
struct SchoolYear: Equatable, Hashable, Identifiable, Sendable {
    /// The calendar year the school year starts in (2025 for "2025–2026").
    let beginYear: Int
    /// Start-of-day of the configured start (begin­Year, startMonth, startDay).
    let start: Date
    /// Start-of-day of the next year's start — exclusive.
    let end: Date

    /// Stable storage key, e.g. "2025-2026".
    var key: String { "\(beginYear)-\(beginYear + 1)" }
    /// Display label with an en dash, e.g. "2025–2026".
    var label: String { "\(beginYear)–\(beginYear + 1)" }
    var id: String { key }
    var range: DateRange { DateRange(start: start, end: end) }
}

extension SchoolYear {
    /// The school year that contains `date`, given a configurable start month/day.
    static func containing(
        _ date: Date,
        startMonth: Int,
        startDay: Int,
        calendar: Calendar
    ) -> SchoolYear {
        let calYear = calendar.component(.year, from: date)
        let startThisCalYear = boundaryDate(year: calYear, month: startMonth, day: startDay, calendar: calendar)
        let begin = (date >= startThisCalYear) ? calYear : (calYear - 1)
        return beginning(in: begin, startMonth: startMonth, startDay: startDay, calendar: calendar)
    }

    /// The school year that begins in calendar year `beginYear`.
    static func beginning(
        in beginYear: Int,
        startMonth: Int,
        startDay: Int,
        calendar: Calendar
    ) -> SchoolYear {
        SchoolYear(
            beginYear: beginYear,
            start: boundaryDate(year: beginYear, month: startMonth, day: startDay, calendar: calendar),
            end: boundaryDate(year: beginYear + 1, month: startMonth, day: startDay, calendar: calendar)
        )
    }

    /// Builds the start-of-day boundary for (year, month, day), retreating the day to the last
    /// valid day of the month if an invalid combination is requested (e.g. Feb 31 → Feb 28/29).
    static func boundaryDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        let clampedMonth = min(max(month, 1), 12)
        var day = min(max(day, 1), 31)
        while day >= 1 {
            var comps = DateComponents()
            comps.year = year
            comps.month = clampedMonth
            comps.day = day
            if let date = calendar.date(from: comps),
               calendar.component(.day, from: date) == day,
               calendar.component(.month, from: date) == clampedMonth {
                return calendar.startOfDay(for: date)
            }
            day -= 1
        }
        let fallback = calendar.date(from: DateComponents(year: year, month: clampedMonth, day: 1))
        return calendar.startOfDay(for: fallback ?? Date(timeIntervalSince1970: 0))
    }
}

/// The active viewing lens. `.allTime` resolves to *no* date filter (today's behavior).
enum SchoolYearSelection: Equatable, Sendable {
    case year(SchoolYear)
    /// A rolling cycle: the anchor year plus the years immediately preceding it.
    case cycle(anchor: SchoolYear)
    case allTime
}
