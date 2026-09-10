// CurriculumTimeline.swift
// The time axis of the Three-Year View: a child's years in the environment,
// counted from her start date, subdivided into terms or months at the zoom
// the guide chooses. Pure date maths, pinned by CurriculumMapEngineTests.

import Foundation

/// How finely a year is divided.
nonisolated enum CurriculumZoom: String, CaseIterable, Sendable, Identifiable {
    case years
    case terms
    case months

    var id: String { rawValue }

    var label: String {
        switch self {
        case .years: "Years"
        case .terms: "Terms"
        case .months: "Months"
        }
    }

    var columnsPerYear: Int {
        switch self {
        case .years: 1
        case .terms: 3
        case .months: 12
        }
    }

    var monthsPerColumn: Int { 12 / columnsPerYear }
}

/// One column of the grid: a half-open date range inside one enrollment year.
nonisolated struct CurriculumColumn: Sendable, Hashable, Identifiable {
    let index: Int
    let start: Date
    let end: Date
    /// 1-based enrollment year the column belongs to.
    let year: Int
    /// Short header text — "Year 2", "Nov–Feb", "Mar ’26".
    let label: String
    /// Longer text for tooltips — the full date range.
    let detail: String
    let isFuture: Bool

    var id: Int { index }

    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

/// The columns for one child.
nonisolated struct CurriculumTimeline: Sendable, Hashable {
    /// The date years are counted from: the child's start date, or an estimate.
    let anchor: Date
    /// True when no start date is on file and `anchor` came from her earliest record.
    let anchorIsEstimated: Bool
    let zoom: CurriculumZoom
    /// 1-based enrollment year today, not clamped — a fourth year is 4.
    let currentYear: Int
    /// Years drawn: at least three, more if she stayed.
    let yearCount: Int
    let columns: [CurriculumColumn]

    /// The elementary cycle. A year beyond it is shown as "3+".
    static let cycleYears = 3

    /// 1-based enrollment year for a date: whole years elapsed since `anchor`, plus one.
    static func enrollmentYear(anchor: Date, on date: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: anchor)
        let day = calendar.startOfDay(for: date)
        guard day >= start else { return 1 }
        let months = calendar.dateComponents([.month], from: start, to: day).month ?? 0
        return months / 12 + 1
    }

    /// "Year 1", "Year 2", "Year 3", then "Year 3+".
    static func yearBadge(_ year: Int) -> String {
        year > cycleYears ? "Year \(cycleYears)+" : "Year \(max(year, 1))"
    }

    static func make(
        dateStarted: Date?,
        fallbackAnchor: Date?,
        today: Date,
        zoom: CurriculumZoom,
        calendar: Calendar
    ) -> CurriculumTimeline {
        let anchor = calendar.startOfDay(for: dateStarted ?? fallbackAnchor ?? today)
        let currentYear = enrollmentYear(anchor: anchor, on: today, calendar: calendar)
        let yearCount = max(cycleYears, currentYear)
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        var columns: [CurriculumColumn] = []
        for year in 1...yearCount {
            for slot in 0..<zoom.columnsPerYear {
                let offset = (year - 1) * 12 + slot * zoom.monthsPerColumn
                guard let start = calendar.date(byAdding: .month, value: offset, to: anchor),
                      let end = calendar.date(byAdding: .month, value: zoom.monthsPerColumn, to: start)
                else { continue }
                columns.append(CurriculumColumn(
                    index: columns.count,
                    start: start,
                    end: end,
                    year: year,
                    label: label(for: zoom, year: year, start: start, end: end, formatter: formatter),
                    detail: detail(start: start, end: end, formatter: formatter),
                    isFuture: start > today
                ))
            }
        }
        return CurriculumTimeline(
            anchor: anchor,
            anchorIsEstimated: dateStarted == nil,
            zoom: zoom,
            currentYear: currentYear,
            yearCount: yearCount,
            columns: columns
        )
    }

    /// The column a date falls in, if it is inside the drawn years.
    func columnIndex(for date: Date) -> Int? {
        guard let first = columns.first, let last = columns.last else { return nil }
        guard date >= first.start, date < last.end else { return nil }
        // Columns are equal-width in months, so a binary search is not worth
        // its own bugs at 36 entries.
        return columns.first { $0.contains(date) }?.index
    }

    var columnsByYear: [(year: Int, columns: [CurriculumColumn])] {
        (1...yearCount).map { year in (year, columns.filter { $0.year == year }) }
    }

    // MARK: - Labels

    private static func label(
        for zoom: CurriculumZoom, year: Int, start: Date, end: Date, formatter: DateFormatter
    ) -> String {
        switch zoom {
        case .years:
            return yearBadge(year)
        case .terms:
            formatter.setLocalizedDateFormatFromTemplate("MMM")
            let lastMonth = formatter.calendar.date(byAdding: .month, value: -1, to: end) ?? end
            return "\(formatter.string(from: start))–\(formatter.string(from: lastMonth))"
        case .months:
            formatter.setLocalizedDateFormatFromTemplate("MMM yy")
            return formatter.string(from: start)
        }
    }

    private static func detail(start: Date, end: Date, formatter: DateFormatter) -> String {
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        let lastDay = formatter.calendar.date(byAdding: .day, value: -1, to: end) ?? end
        return "\(formatter.string(from: start)) – \(formatter.string(from: lastDay))"
    }
}
