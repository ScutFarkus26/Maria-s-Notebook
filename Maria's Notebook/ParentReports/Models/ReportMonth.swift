// ReportMonth.swift
// Calendar-month value type for the monthly parent report cycle.

import Foundation

/// One calendar month of classroom records, identified by a stable
/// `monthKey` like "2026-09". Pure value type; the calendar is always
/// injected so month/DST boundaries stay testable.
struct ReportMonth: Equatable, Hashable, Identifiable, Sendable {
    let year: Int
    let month: Int

    var id: String { monthKey }

    /// Stable storage key, e.g. "2026-09".
    var monthKey: String {
        String(format: "%04d-%02d", year, month)
    }

    /// "September 2026" in the current locale.
    var displayName: String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let calendar = AppCalendar.shared
        guard let date = calendar.date(from: components) else { return monthKey }
        return date.formatted(.dateTime.month(.wide).year())
    }

    var previous: ReportMonth {
        month == 1 ? ReportMonth(year: year - 1, month: 12) : ReportMonth(year: year, month: month - 1)
    }

    var next: ReportMonth {
        month == 12 ? ReportMonth(year: year + 1, month: 1) : ReportMonth(year: year, month: month + 1)
    }

    /// Half-open interval covering the month.
    func dateInterval(calendar: Calendar) -> DateInterval {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let start = calendar.date(from: components) ?? Date()
        return calendar.dateInterval(of: .month, for: start) ?? DateInterval(start: start, duration: 0)
    }

    /// Closed range for predicates written against `>= start AND <= end`
    /// (e.g. `ReportGeneratorService.fetchReportNotes`). The upper bound is
    /// one second before the next month starts.
    func closedRange(calendar: Calendar) -> ClosedRange<Date> {
        let interval = dateInterval(calendar: calendar)
        let end = interval.end.addingTimeInterval(-1)
        return interval.start...max(interval.start, end)
    }

    /// The reporting cycle for this month: opens on day 1 of the following
    /// month and is due through the end of day 7.
    func cycleWindow(calendar: Calendar) -> DateInterval {
        let nextInterval = next.dateInterval(calendar: calendar)
        let start = nextInterval.start
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func containing(_ date: Date, calendar: Calendar) -> ReportMonth {
        let components = calendar.dateComponents([.year, .month], from: date)
        return ReportMonth(year: components.year ?? 2000, month: components.month ?? 1)
    }

    /// The cycle currently open for reporting: last month's records.
    static func currentCycle(now: Date = Date(), calendar: Calendar = AppCalendar.shared) -> ReportMonth {
        containing(now, calendar: calendar).previous
    }

    static func parse(monthKey: String) -> ReportMonth? {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else { return nil }
        return ReportMonth(year: year, month: month)
    }
}
