//
//  YearPlanStaleness.swift
//  Cosmic Daybook
//
//  Last year's intentions, told apart from this year's debt.
//
//  A year-plan entry is a day the guide meant to give a lesson. When that day
//  passes with the lesson still ahead of the child, the entry is behind pace —
//  a real, actionable number. But an entry whose target fell in *April* is not
//  four months of debt: it is a plan made for a school year that has since
//  ended. Counting it as behind pace is what leaves a child opening the year
//  with ten red entries she was never going to be given, and makes the whole
//  pace summary unreadable.
//
//  The rule is one comparison against the start of the school year containing
//  today. Carried over iff the entry is still `planned`, has a target date,
//  and that date falls strictly before the year start. A target on the start
//  day itself is this year's. `.promoted` is a real assignment on the calendar
//  and `.skipped` is the guide's own decision, so neither is ever carried over.
//  Whether the record already answers the entry is a separate question
//  (`YearPlanSatisfaction`), asked by the caller, so this rule stays free of
//  Core Data and is trivially testable.
//
//  Nothing is stored. A flag would have to be written by whichever device
//  first noticed the boundary, and `CDYearPlanEntry` lives in the private
//  store — the same argument `YearPlanSatisfaction` makes at length. Re-dating
//  writes `plannedDate` and skipping writes `statusRaw`; both already exist.
//
//  `currentYearStart()` is read inside `isBehindPace`, which the year-plan
//  calendar evaluates per cell per render, so the answer is cached behind an
//  `NSLock` keyed on the configured start and today — the shape
//  `SchoolDayDataVersion` and `SchoolYearCounters.epoch` already use. Hot call
//  sites should still compute the start once per load and pass it down rather
//  than leaning on the default argument.
//

import Foundation

nonisolated enum YearPlanStaleness {

    /// Which school year an intention belongs to.
    enum Vintage: String, Sendable, Equatable {
        /// This school year's plan: pace applies to it.
        case current
        /// Last year's plan, left behind by the boundary: not debt.
        case carriedOver
    }

    // MARK: - The rule

    static func classify(
        plannedDate: Date?, status: YearPlanEntryStatus, yearStart: Date
    ) -> Vintage {
        guard status == .planned, let plannedDate else { return .current }
        return AppCalendar.startOfDay(plannedDate) < AppCalendar.startOfDay(yearStart)
            ? .carriedOver
            : .current
    }

    static func isCarriedOver(
        plannedDate: Date?, status: YearPlanEntryStatus, yearStart: Date
    ) -> Bool {
        classify(plannedDate: plannedDate, status: status, yearStart: yearStart) == .carriedOver
    }

    // MARK: - The boundary

    /// Start-of-day of the school year containing `asOf`, read from the same
    /// `SchoolYearStore` defaults the viewing lens uses (September 1 unless the
    /// guide moved it).
    static func currentYearStart(asOf: Date = Date(), calendar: Calendar = AppCalendar.shared) -> Date {
        schoolYear(containing: asOf, calendar: calendar).start
    }

    /// The whole school year containing `date` — the label surfaces need
    /// ("carried over from 2025–2026") as well as its start.
    static func schoolYear(
        containing date: Date, calendar: Calendar = AppCalendar.shared
    ) -> SchoolYear {
        let (month, day) = configuredStart()
        let key = CacheKey(startMonth: month, startDay: day, day: calendar.startOfDay(for: date))
        if let hit = cached(for: key) { return hit }
        let year = SchoolYear.containing(
            date, startMonth: month, startDay: day, calendar: calendar
        )
        store(year, for: key)
        return year
    }

    /// The school year immediately before the one containing `date` — the year
    /// a carried-over entry was planned in, for the "from 2025–2026" label.
    static func previousSchoolYear(
        containing date: Date = Date(), calendar: Calendar = AppCalendar.shared
    ) -> SchoolYear {
        let current = schoolYear(containing: date, calendar: calendar)
        let (month, day) = configuredStart()
        return SchoolYear.beginning(
            in: current.beginYear - 1, startMonth: month, startDay: day, calendar: calendar
        )
    }

    // MARK: - Cache

    private struct CacheKey: Hashable {
        let startMonth: Int
        let startDay: Int
        let day: Date
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedKey: CacheKey?
    nonisolated(unsafe) private static var cachedYear: SchoolYear?

    private static func cached(for key: CacheKey) -> SchoolYear? {
        lock.lock(); defer { lock.unlock() }
        return cachedKey == key ? cachedYear : nil
    }

    private static func store(_ year: SchoolYear, for key: CacheKey) {
        lock.lock(); defer { lock.unlock() }
        cachedKey = key
        cachedYear = year
    }

    /// Drops the memoized boundary. Only the settings that move the school-year
    /// start need this; the key already covers the day rolling over.
    static func invalidateCache() {
        lock.lock(); defer { lock.unlock() }
        cachedKey = nil
        cachedYear = nil
    }

    /// The configured start month/day, defaulted exactly as `SchoolYearStore`
    /// defaults them so the two can never disagree.
    private static func configuredStart() -> (month: Int, day: Int) {
        let defaults = UserDefaults.standard
        let month = defaults.object(forKey: UserDefaultsKeys.schoolYearStartMonth) as? Int
        let day = defaults.object(forKey: UserDefaultsKeys.schoolYearStartDay) as? Int
        let resolvedMonth = (month.map { (1...12).contains($0) ? $0 : 9 }) ?? 9
        let resolvedDay = (day.map { (1...31).contains($0) ? $0 : 1 }) ?? 1
        return (resolvedMonth, resolvedDay)
    }
}
