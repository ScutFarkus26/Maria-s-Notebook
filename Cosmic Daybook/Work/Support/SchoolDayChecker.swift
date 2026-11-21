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
/// 2. A day the school session is out on (`SchoolSession.isOut`) is
///    non-school, whatever the weekday (domain-logic review R20).
/// 3. Weekdays are school days.
/// 4. A SchoolDayOverride makes a weekend count as a school day.
/// 5. Weekends are non-school by default.
enum SchoolDayChecker {

    /// The school-day rule applied to pre-fetched record sets. Cache layers
    /// that bulk-load NonSchoolDay/SchoolDayOverride dates call this per day
    /// instead of restating the precedence themselves. Both sets must contain
    /// start-of-day dates normalized with `calendar`.
    nonisolated static func isNonSchoolDay(
        _ date: Date,
        nonSchoolDayDates: Set<Date>,
        overrideDates: Set<Date>,
        session: SchoolSession? = nil,
        calendar: Calendar = AppCalendar.shared
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        if nonSchoolDayDates.contains(day) { return true }
        if session?.isOut(day, calendar: calendar) == true { return true }
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
        let session = SchoolSession.read(in: context)

        var result: Set<Date> = []
        var cursor = start
        var iterations = 0
        let maxIterations = 36500
        while cursor < end && iterations < maxIterations {
            if isNonSchoolDay(
                cursor,
                nonSchoolDayDates: nonSchoolDates,
                overrideDates: overrideDates,
                session: session,
                calendar: calendar
            ) {
                result.insert(cursor)
            }
            let next = AppCalendar.dayStart(after: cursor, calendar: calendar)
            guard next > cursor else { break }
            cursor = next
            iterations += 1
        }
        return result
    }

    /// Determines if a given date is a non-school day.
    nonisolated static func isNonSchoolDay(_ date: Date, using context: NSManagedObjectContext) -> Bool {
        isNonSchoolDay(date, session: SchoolSession.read(in: context), using: context)
    }

    /// The per-day rule with the session already read, for a walk over
    /// several days (`nextSchoolDays`, `schoolDay(from:forward:using:)`).
    nonisolated static func isNonSchoolDay(
        _ date: Date, session: SchoolSession?, using context: NSManagedObjectContext
    ) -> Bool {
        let cal = AppCalendar.shared
        let day = cal.startOfDay(for: date)

        // Same precedence as the set-based rule above, but with short-circuit
        // fetches so single-day checks don't query overrides on weekdays.
        if hasNonSchoolDayRecord(for: day, using: context) {
            return true
        }
        if session?.isOut(day, calendar: cal) == true { return true }

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
    /// Two fetches for the whole range (`nonSchoolDaySet`), not two per day.
    nonisolated static func schoolDaysBetween(
        start: Date,
        end: Date,
        using context: NSManagedObjectContext
    ) -> Int {
        let calendar = AppCalendar.shared
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        guard startDay < endDay else { return 0 }

        let daysOff = nonSchoolDaySet(in: startDay..<endDay, using: context, calendar: calendar)
        var count = 0
        var cursor = startDay

        let maxIterations = 36500
        var iterations = 0

        while cursor < endDay && iterations < maxIterations {
            if !daysOff.contains(cursor) {
                count += 1
            }
            cursor = AppCalendar.dayStart(after: cursor, calendar: calendar)
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
        let session = SchoolSession.read(in: context)

        let maxIterations = 1000
        var iterations = 0

        while result.count < count && iterations < maxIterations {
            if !isNonSchoolDay(cursor, session: session, using: context) {
                result.append(cursor)
            }
            cursor = AppCalendar.addingDays(1, to: cursor)
            iterations += 1
        }

        return result
    }

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
        hasRecord(CDNonSchoolDay.self, on: day, using: context)
    }

    private nonisolated static func hasSchoolDayOverride(for day: Date, using context: NSManagedObjectContext) -> Bool {
        hasRecord(CDSchoolDayOverride.self, on: day, using: context)
    }

    /// Any record of `type` dated within `day`, as the set-based form reads
    /// them: a record stored at a time other than midnight (an older build,
    /// another time zone) still marks its day. This used to match the exact
    /// instant, so such a holiday counted in the cached calendar and was a
    /// school day everywhere that asked about one day.
    private nonisolated static func hasRecord<T: NSManagedObject>(
        _ type: T.Type, on day: Date, using context: NSManagedObjectContext
    ) -> Bool {
        let next = AppCalendar.addingDays(1, to: day)
        let request = CDFetchRequest(T.self)
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", day as NSDate, next as NSDate)
        request.fetchLimit = 1
        return !context.safeFetch(request).isEmpty
    }
}

/// The school session the guide set in Settings › School Year: its first and
/// last days, carried on the shared settings row (schema 25) so the Daybook
/// Assistant reads them too (domain-logic review R20). Only a whole session
/// counts: with either day missing, or the two out of order, there is none,
/// and every reader keeps the behavior from before sessions.
nonisolated struct SchoolSession: Equatable, Sendable {
    let firstDay: Date
    let lastDay: Date

    init?(firstDay: Date?, lastDay: Date?) {
        guard let firstDay, let lastDay, firstDay <= lastDay else { return nil }
        self.firstDay = firstDay
        self.lastDay = lastDay
    }

    /// Whether school is out on `day` by the session: the summer after the
    /// last day, until a year after the first day, and the summer before the
    /// first day, back to July 1 (where `AttendanceSchoolDayCount` starts
    /// looking for a year's first day).
    ///
    /// Days further off are another school year, which one session says
    /// nothing about, so they keep the weekday rule: last year's school days
    /// stay school days for its attendance totals, and a session nobody
    /// brought up to date stops closing days once its year is over.
    func isOut(_ day: Date, calendar: Calendar = AppCalendar.shared) -> Bool {
        let day = calendar.startOfDay(for: day)
        let first = calendar.startOfDay(for: firstDay)
        let last = calendar.startOfDay(for: lastDay)
        if day > last {
            guard let nextYear = calendar.date(byAdding: .year, value: 1, to: first) else { return false }
            return day < nextYear
        }
        guard day < first else { return false }
        let year = calendar.component(.year, from: first)
        let startYear = calendar.component(.month, from: first) >= 7 ? year : year - 1
        guard let summer = calendar.date(from: DateComponents(year: startYear, month: 7, day: 1)) else { return false }
        return day >= summer
    }

    /// The session's first day when `date` falls in the year that begins on
    /// it: what the school year's start reads (`SchoolYear.currentStart`).
    func yearStart(containing date: Date, calendar: Calendar = AppCalendar.shared) -> Date? {
        let first = calendar.startOfDay(for: firstDay)
        guard date >= first, let nextYear = calendar.date(byAdding: .year, value: 1, to: first),
              date < nextYear else { return nil }
        return first
    }

    /// The session on `context`'s settings row: the newest that holds one
    /// (there is one row, or two while two of the guide's devices have each
    /// written one). In the Assistant the classroom share's only, as its days
    /// off are read (`AttendanceEmailLog.scopeToClassroom`).
    static func read(in context: NSManagedObjectContext) -> SchoolSession? {
        let request = CDFetchRequest(CDAttendanceEmailSettings.self)
        request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        #if ASSISTANT_APP
        let shared = context.persistentStoreCoordinator?.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
        if let shared { request.affectedStores = [shared] }
        #endif
        return context.safeFetch(request).lazy
            .compactMap { SchoolSession(firstDay: $0.sessionFirstDay, lastDay: $0.sessionLastDay) }
            .first
    }
}
