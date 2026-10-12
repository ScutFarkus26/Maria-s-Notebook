// CurriculumTimeline.swift
// The time axis of the Three-Year View: a child's years in the environment,
// counted in school years from the one she started in, subdivided into terms
// or months at the zoom the guide chooses. Pure date maths, pinned by
// CurriculumMapEngineTests; the overloads without a start month and day read
// the configured school-year start (Settings › School year).

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

/// One column of the grid: a half-open date range inside one school year.
nonisolated struct CurriculumColumn: Sendable, Hashable, Identifiable {
    let index: Int
    let start: Date
    let end: Date
    /// 1-based school year of hers the column belongs to.
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
    /// Her start date, or an estimate. Her first year is the school year it
    /// falls in, or the next when it falls in the last `earlyStartDays` before it.
    let anchor: Date
    /// True when no start date is on file and `anchor` came from her earliest record.
    let anchorIsEstimated: Bool
    let zoom: CurriculumZoom
    /// 1-based school year of hers today, not clamped — a fourth year is 4.
    let currentYear: Int
    /// Years drawn: at least three, more if she stayed.
    let yearCount: Int
    let columns: [CurriculumColumn]

    /// The elementary cycle. A year beyond it is shown as "3+".
    static let cycleYears = 3

    /// 1-based year of hers on `date`, by the configured school-year start.
    static func enrollmentYear(anchor: Date, on date: Date, calendar: Calendar) -> Int {
        let start = configuredSchoolYearStart()
        return enrollmentYear(
            anchor: anchor, on: date, startMonth: start.month, startDay: start.day, calendar: calendar
        )
    }

    /// 1-based year of hers on `date`: school years begun since the one she
    /// started in, plus one. A child who joined in January is in her second
    /// year from the next school-year start, as she is everywhere else in the
    /// app, not from the anniversary of her first day.
    static func enrollmentYear(
        anchor: Date, on date: Date, startMonth: Int, startDay: Int, calendar: Calendar
    ) -> Int {
        guard calendar.startOfDay(for: date) >= calendar.startOfDay(for: anchor) else { return 1 }
        let first = firstSchoolYear(anchor: anchor, startMonth: startMonth, startDay: startDay, calendar: calendar)
        let current = SchoolYear.containing(date, startMonth: startMonth, startDay: startDay, calendar: calendar)
        return max(current.beginYear - first.beginYear + 1, 1)
    }

    /// How close before a school-year start a start date still counts as that
    /// year: a child whose start date is a few days before the year began
    /// (the 24th for a year starting the 25th) started with it, not a year
    /// before it.
    static let earlyStartDays = 30

    /// The school year she started in: the one containing her start date plus
    /// `earlyStartDays` (bug hunt 2026-10-12 review, #34).
    static func firstSchoolYear(anchor: Date, startMonth: Int, startDay: Int, calendar: Calendar) -> SchoolYear {
        let shifted = calendar.date(byAdding: .day, value: earlyStartDays, to: calendar.startOfDay(for: anchor))
            ?? anchor
        return SchoolYear.containing(shifted, startMonth: startMonth, startDay: startDay, calendar: calendar)
    }

    /// "Year 1", "Year 2", "Year 3", then "Year 3+".
    static func yearBadge(_ year: Int) -> String {
        year > cycleYears ? "Year \(cycleYears)+" : "Year \(max(year, 1))"
    }

    /// The timeline by the configured school-year start.
    static func make(
        dateStarted: Date?,
        fallbackAnchor: Date?,
        today: Date,
        zoom: CurriculumZoom,
        calendar: Calendar
    ) -> CurriculumTimeline {
        let start = configuredSchoolYearStart()
        return make(
            dateStarted: dateStarted, fallbackAnchor: fallbackAnchor, today: today, zoom: zoom,
            startMonth: start.month, startDay: start.day, calendar: calendar
        )
    }

    /// Year columns are her school years, from the start of the one she
    /// joined in; terms and months divide each from its own first day. Every
    /// column ends where the next begins (both are offsets from the year's
    /// start, never a clamped start plus a width), so a year beginning on the
    /// 29th–31st leaves no days out.
    static func make( // swiftlint:disable:this function_parameter_count
        dateStarted: Date?,
        fallbackAnchor: Date?,
        today: Date,
        zoom: CurriculumZoom,
        startMonth: Int,
        startDay: Int,
        calendar: Calendar
    ) -> CurriculumTimeline {
        let anchor = calendar.startOfDay(for: dateStarted ?? fallbackAnchor ?? today)
        let currentYear = enrollmentYear(
            anchor: anchor, on: today, startMonth: startMonth, startDay: startDay, calendar: calendar
        )
        let yearCount = max(cycleYears, currentYear)
        let firstBeginYear = firstSchoolYear(
            anchor: anchor, startMonth: startMonth, startDay: startDay, calendar: calendar
        ).beginYear
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        var columns: [CurriculumColumn] = []
        for year in 1...yearCount {
            let schoolYear = SchoolYear.beginning(
                in: firstBeginYear + year - 1, startMonth: startMonth, startDay: startDay, calendar: calendar
            )
            func boundary(_ slot: Int) -> Date? {
                guard slot < zoom.columnsPerYear else { return schoolYear.end }
                // A start in the days before her first year began opens its
                // first column, so her first records are still drawn.
                if year == 1, slot == 0 { return min(anchor, schoolYear.start) }
                return calendar.date(byAdding: .month, value: slot * zoom.monthsPerColumn, to: schoolYear.start)
            }
            for slot in 0..<zoom.columnsPerYear {
                guard let start = boundary(slot), let end = boundary(slot + 1) else { continue }
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

    /// The school-year start month and day, defaulted as `SchoolYearStore`
    /// defaults them (September 1) so the two never disagree.
    private static func configuredSchoolYearStart() -> (month: Int, day: Int) {
        let defaults = UserDefaults.standard
        let month = defaults.object(forKey: UserDefaultsKeys.schoolYearStartMonth) as? Int
        let day = defaults.object(forKey: UserDefaultsKeys.schoolYearStartDay) as? Int
        let resolvedMonth = (month.map { (1...12).contains($0) ? $0 : 9 }) ?? 9
        let resolvedDay = (day.map { (1...31).contains($0) ? $0 : 1 }) ?? 1
        return (resolvedMonth, resolvedDay)
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
