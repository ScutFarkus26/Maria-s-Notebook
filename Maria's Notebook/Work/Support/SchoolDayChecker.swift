import Foundation
import CoreData

/// Canonical implementation of the school-day rules. The cache layer
/// (`SchoolCalendarService`) and engines that hold their own record sets
/// route their decisions through this type so the rules cannot drift
/// between screens.
///
/// Rules, in precedence order:
/// 1. An explicit NonSchoolDay record makes any date non-school
///    (it beats a SchoolDayOverride on the same date).
/// 2. Weekdays are school days.
/// 3. A SchoolDayOverride makes a weekend count as a school day.
/// 4. Weekends are non-school by default.
enum SchoolDayChecker {

    /// The school-day rule applied to pre-fetched record sets. Cache layers
    /// that bulk-load NonSchoolDay/SchoolDayOverride dates call this per day
    /// instead of restating the precedence themselves. Both sets must contain
    /// start-of-day dates normalized with `calendar`.
    nonisolated static func isNonSchoolDay(
        _ date: Date,
        nonSchoolDayDates: Set<Date>,
        overrideDates: Set<Date>,
        calendar: Calendar = AppCalendar.shared
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        if nonSchoolDayDates.contains(day) { return true }
        let weekday = calendar.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }
        return !overrideDates.contains(day)
    }

    /// The set of non-school days in `range`, computed from two bulk fetches
    /// instead of two fetches per day. `SchoolDayCheckerTests` cross-checks
    /// this against the per-day variant so the two forms cannot diverge.
    nonisolated static func nonSchoolDaySet(
        in range: Range<Date>,
        using context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> Set<Date> {
        let start = calendar.startOfDay(for: range.lowerBound)
        let end = calendar.startOfDay(for: range.upperBound)
        guard start < end else { return [] }

        let nonSchoolDates = recordDates(
            CDNonSchoolDay.self, start: start, end: end, using: context, calendar: calendar
        )
        let overrideDates = recordDates(
            CDSchoolDayOverride.self, start: start, end: end, using: context, calendar: calendar
        )

        var result: Set<Date> = []
        var cursor = start
        var iterations = 0
        let maxIterations = 36500
        while cursor < end && iterations < maxIterations {
            if isNonSchoolDay(
                cursor,
                nonSchoolDayDates: nonSchoolDates,
                overrideDates: overrideDates,
                calendar: calendar
            ) {
                result.insert(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
            iterations += 1
        }
        return result
    }

    /// Determines if a given date is a non-school day.
    nonisolated static func isNonSchoolDay(_ date: Date, using context: NSManagedObjectContext) -> Bool {
        let day = AppCalendar.startOfDay(date)
        let cal = AppCalendar.shared

        // Same precedence as the set-based rule above, but with short-circuit
        // fetches so single-day checks don't query overrides on weekdays.
        if hasNonSchoolDayRecord(for: day, using: context) {
            return true
        }

        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }

        if hasSchoolDayOverride(for: day, using: context) {
            return false
        }

        return true
    }

    /// Determines if a given date is a school day (inverse of isNonSchoolDay).
    nonisolated static func isSchoolDay(_ date: Date, using context: NSManagedObjectContext) -> Bool {
        !isNonSchoolDay(date, using: context)
    }

    /// Counts the number of school days between two dates (exclusive of end date).
    nonisolated static func schoolDaysBetween(
        start: Date,
        end: Date,
        using context: NSManagedObjectContext
    ) -> Int {
        let startDay = AppCalendar.startOfDay(start)
        let endDay = AppCalendar.startOfDay(end)

        guard startDay < endDay else { return 0 }

        var count = 0
        var cursor = startDay

        let maxIterations = 36500
        var iterations = 0

        while cursor < endDay && iterations < maxIterations {
            if isSchoolDay(cursor, using: context) {
                count += 1
            }
            cursor = AppCalendar.addingDays(1, to: cursor)
            iterations += 1
        }

        return count
    }

    /// Computes a list of school days starting from a given date.
    nonisolated static func nextSchoolDays(
        from startDate: Date,
        count: Int,
        using context: NSManagedObjectContext
    ) -> [Date] {
        var result: [Date] = []
        var cursor = AppCalendar.startOfDay(startDate)

        let maxIterations = 1000
        var iterations = 0

        while result.count < count && iterations < maxIterations {
            if isSchoolDay(cursor, using: context) {
                result.append(cursor)
            }
            cursor = AppCalendar.addingDays(1, to: cursor)
            iterations += 1
        }

        return result
    }

    // Deprecated ModelContext overloads removed - no longer needed with Core Data.

    // MARK: - Private Helpers

    /// Start-of-day dates of all records of `type` whose date falls in
    /// [start, end). Dates are re-normalized so records stored at non-midnight
    /// times (older app versions, other time zones) still match day cursors.
    private nonisolated static func recordDates<T: NSManagedObject>(
        _ type: T.Type,
        start: Date,
        end: Date,
        using context: NSManagedObjectContext,
        calendar: Calendar
    ) -> Set<Date> {
        let request = CDFetchRequest(T.self)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@",
            start as NSDate, end as NSDate
        )
        let records = context.safeFetch(request)
        return Set(records.compactMap { record in
            (record.value(forKey: "date") as? Date).map { calendar.startOfDay(for: $0) }
        })
    }

    private nonisolated static func hasNonSchoolDayRecord(
        for day: Date,
        using context: NSManagedObjectContext
    ) -> Bool {
        let request = CDFetchRequest(CDNonSchoolDay.self)
        request.predicate = NSPredicate(format: "date == %@", day as NSDate)
        request.fetchLimit = 1
        return !context.safeFetch(request).isEmpty
    }

    private nonisolated static func hasSchoolDayOverride(for day: Date, using context: NSManagedObjectContext) -> Bool {
        let request = CDFetchRequest(CDSchoolDayOverride.self)
        request.predicate = NSPredicate(format: "date == %@", day as NSDate)
        request.fetchLimit = 1
        return !context.safeFetch(request).isEmpty
    }
}
