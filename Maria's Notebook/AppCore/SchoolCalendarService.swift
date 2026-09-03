import Foundation
import CoreData
import OSLog

/// The app's single school-day cache. Every screen that asks "is this a
/// school day?" — Today, Attendance, Agenda, Planning, work aging — goes
/// through this service, which caches the answer per month and applies the
/// rules in `SchoolDayChecker` (explicit NonSchoolDay → weekend → override).
///
/// Invalidation: `AppDependencies` clears the cache on `.schoolDayDataDidChange`
/// (a local edit, a CloudKit sync, or a backup restore) and bumps
/// `SchoolDayDataVersion`; the service also checks that version lazily on every
/// lookup, so a stale month is never served even if the observer fires late.
///
/// `@MainActor` to align with NSManagedObjectContext thread requirements in
/// Swift 6. Nonisolated callers (model initializers, engines that already hold
/// their own record sets) use `SchoolDayChecker` directly.
@MainActor
public final class SchoolCalendarService {
    public static let shared = SchoolCalendarService()

    // MARK: - State

    /// Start-of-month date -> non-school start-of-day dates within that month.
    private var monthSets: [Date: Set<Date>] = [:]
    /// Memoized `schoolDaysBetween` results, keyed by their [start, end) day range.
    private var schoolDayCounts: [Range<Date>: Int] = [:]
    /// The `SchoolDayDataVersion` the caches were built against.
    private var dataVersion: Int = SchoolDayDataVersion.current

    // MARK: - Calendar

    private var cal: Calendar { AppCalendar.shared }

    private func monthKey(for date: Date) -> Date {
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    private func monthRange(containing date: Date) -> Range<Date> {
        let start = monthKey(for: date)
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return start ..< end
    }

    // MARK: - Cache Helpers

    private func invalidateMonthCache(for date: Date) {
        monthSets.removeValue(forKey: monthKey(for: date))
        schoolDayCounts.removeAll()
    }

    /// Clears every cached month and count. Use when school-day data may have
    /// changed in bulk (a CloudKit sync or a restore) rather than at a single
    /// known date.
    public func invalidateCache() {
        monthSets.removeAll()
        schoolDayCounts.removeAll()
    }

    /// Drops the caches if school-day data changed since they were built.
    private func dropCachesIfStale() {
        let current = SchoolDayDataVersion.current
        guard current != dataVersion else { return }
        dataVersion = current
        invalidateCache()
    }

    /// Announces that school-day data changed so cached school-day calculations
    /// get invalidated. Call after any edit to non-school days / weekend overrides.
    static func notifySchoolDayDataChanged() {
        NotificationCenter.default.post(name: .schoolDayDataDidChange, object: nil)
    }

    private func setForMonth(_ date: Date, using context: NSManagedObjectContext) -> Set<Date> {
        dropCachesIfStale()
        let key = monthKey(for: date)
        if let cached = monthSets[key] {
            return cached
        }
        let set = SchoolDayChecker.nonSchoolDaySet(
            in: monthRange(containing: date), using: context, calendar: cal
        )
        monthSets[key] = set
        return set
    }

    // MARK: - Lookups (synchronous, cached)

    /// Returns true if the given date is a non-school day (weekend or configured
    /// non-school date), taking weekend overrides into account. Synchronous so
    /// it can be called from a `body` pass or a non-async helper.
    public func isNonSchoolDaySync(_ date: Date, using context: NSManagedObjectContext) -> Bool {
        let day = cal.startOfDay(for: date)
        return setForMonth(day, using: context).contains(day)
    }

    /// Returns the next school day strictly after the given date.
    /// Weekends and configured non-school days are skipped; weekend overrides are respected.
    public func nextSchoolDaySync(after date: Date, using context: NSManagedObjectContext) -> Date {
        var d = cal.startOfDay(for: date)
        // Start from the following day
        d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        // Safety cap to avoid infinite loops in case of data errors
        for _ in 0..<730 { // up to ~2 years
            if !isNonSchoolDaySync(d, using: context) { return d }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    /// Returns the previous school day strictly before the given date.
    /// Weekends and configured non-school days are skipped; weekend overrides are respected.
    public func previousSchoolDaySync(before date: Date, using context: NSManagedObjectContext) -> Date {
        var d = cal.startOfDay(for: date)
        // Start from the previous day
        d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        for _ in 0..<730 { // up to ~2 years
            if !isNonSchoolDaySync(d, using: context) { return d }
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    /// Coerces the provided date to the nearest school day.
    /// If the date is already a school day, it is returned unchanged.
    /// Otherwise, the closer of the previous/next school day is chosen
    /// (ties prefer the next day).
    public func nearestSchoolDaySync(to date: Date, using context: NSManagedObjectContext) -> Date {
        let day = cal.startOfDay(for: date)
        if !isNonSchoolDaySync(day, using: context) { return day }
        let prev = previousSchoolDaySync(before: day, using: context)
        let next = nextSchoolDaySync(after: day, using: context)
        let distPrev = abs(prev.timeIntervalSince(day))
        let distNext = abs(next.timeIntervalSince(day))
        if distPrev < distNext { return prev }
        // On tie or next closer, prefer next
        return next
    }

    // MARK: - Batch Helpers

    /// Warms the cache for every month touching `start...end` with one pair of
    /// fetches instead of one per month, so a loop of per-day lookups or
    /// `schoolDaysBetween` calls over the range is pure dictionary work.
    public func preloadNonSchoolDays(from start: Date, to end: Date, using context: NSManagedObjectContext) {
        dropCachesIfStale()
        let firstMonth = monthKey(for: start)
        let lastMonth = monthKey(for: end)
        guard firstMonth <= lastMonth else { return }

        var missing: [Date] = []
        var cursor = firstMonth
        while cursor <= lastMonth {
            if monthSets[cursor] == nil { missing.append(cursor) }
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        guard let firstMissing = missing.first, let lastMissing = missing.last else { return }

        let spanEnd = cal.date(byAdding: .month, value: 1, to: lastMissing) ?? lastMissing
        let span = SchoolDayChecker.nonSchoolDaySet(in: firstMissing..<spanEnd, using: context, calendar: cal)
        let byMonth = Dictionary(grouping: span, by: { monthKey(for: $0) })
        for month in missing {
            monthSets[month] = Set(byMonth[month] ?? [])
        }
    }

    /// Counts the school days in [start, end) from the cache, memoized per range.
    /// Same rule as `SchoolDayChecker.schoolDaysBetween`, without a fetch per day.
    public func schoolDaysBetween(start: Date, end: Date, using context: NSManagedObjectContext) -> Int {
        dropCachesIfStale()
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        guard startDay < endDay else { return 0 }

        let key = startDay..<endDay
        if let cached = schoolDayCounts[key] {
            return cached
        }

        preloadNonSchoolDays(from: startDay, to: endDay, using: context)

        var count = 0
        var cursor = startDay
        var iterations = 0
        let maxIterations = 10000 // ~27 years of days
        while cursor < endDay && iterations < maxIterations {
            iterations += 1
            if !isNonSchoolDaySync(cursor, using: context) {
                count += 1
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        schoolDayCounts[key] = count
        return count
    }

    /// School days since `createdAt`, as of `today`. The start is clamped to the
    /// school-year counter epoch, so an activity from a previous year counts from
    /// the first day of this one (see `SchoolYearCounters`). `schoolDaysBetween`
    /// stays unclamped — it measures explicit ranges, not elapsed counters.
    public func schoolDaysSinceCreation(
        createdAt: Date,
        asOf today: Date = Date(),
        using context: NSManagedObjectContext
    ) -> Int {
        let start = SchoolYearCounters.countFrom(createdAt)
        return schoolDaysBetween(start: start, end: today, using: context)
    }

    // MARK: - Async API

    /// Returns true if the given date is a non-school day (weekend or configured non-school date),
    /// taking weekend overrides into account.
    public func isNonSchoolDay(_ date: Date, using context: NSManagedObjectContext) async -> Bool {
        isNonSchoolDaySync(date, using: context)
    }

    /// Returns a freshly computed set of non-school days in the given range.
    /// Weekends are included by default; weekend overrides are removed; explicit non-school days are included.
    ///
    /// Delegates to the canonical rules in `SchoolDayChecker`. This also fixed
    /// a precedence divergence: this method used to apply weekend overrides
    /// *after* explicit NonSchoolDay records, letting an override turn an
    /// explicit non-school date back into a school day — the opposite of every
    /// other school-day code path.
    public func precomputedNonSchoolSet(
        in range: Range<Date>,
        using context: NSManagedObjectContext
    ) async -> Set<Date> {
        SchoolDayChecker.nonSchoolDaySet(in: range, using: context, calendar: cal)
    }

    /// Returns the set of non-school days in the given range (same as `precomputedNonSchoolSet`).
    public func nonSchoolDays(in range: Range<Date>, using context: NSManagedObjectContext) async -> Set<Date> {
        return await precomputedNonSchoolSet(in: range, using: context)
    }

    /// Toggle the non-school state for a date from the user's perspective.
    /// - For weekdays: toggles a NonSchoolDay record.
    /// - For weekends: toggles a SchoolDayOverride (weekend defaults to non-school; override makes it a school day).
    /// - Returns: The new non-school state after toggling.
    @discardableResult
    public func toggleNonSchoolDay(_ date: Date, using context: NSManagedObjectContext) async throws -> Bool {
        let day = cal.startOfDay(for: date)
        let wd = cal.component(.weekday, from: day)
        let isWeekend = (wd == 1 || wd == 7)

        if isWeekend {
            // Weekend logic
            let overrideFetch: NSFetchRequest<CDSchoolDayOverride> =
                NSFetchRequest<CDSchoolDayOverride>(entityName: "SchoolDayOverride")
            overrideFetch.predicate = NSPredicate(format: "date == %@", day as NSDate)
            overrideFetch.fetchLimit = 1
            let overrides: [CDSchoolDayOverride] = try context.fetch(overrideFetch)

            let becameNonSchool: Bool
            if let existing = overrides.first {
                // Remove override -> weekend becomes non-school again
                context.delete(existing)
                becameNonSchool = true
            } else {
                // Add override -> weekend becomes a school day (non-school = false)
                let override = CDSchoolDayOverride(context: context)
                override.date = day
                becameNonSchool = false
            }
            // Save is handled by caller or autosave - no immediate save needed
            invalidateMonthCache(for: day)
            Self.notifySchoolDayDataChanged()
            return becameNonSchool
        } else {
            // Weekday logic
            let nsFetch: NSFetchRequest<CDNonSchoolDay> = NSFetchRequest<CDNonSchoolDay>(entityName: "NonSchoolDay")
            nsFetch.predicate = NSPredicate(format: "date == %@", day as NSDate)
            nsFetch.fetchLimit = 1
            let items: [CDNonSchoolDay] = try context.fetch(nsFetch)

            let isNowNonSchool: Bool
            if let existing = items.first {
                // Remove explicit non-school -> becomes school day
                context.delete(existing)
                isNowNonSchool = false
            } else {
                // Add explicit non-school for weekday
                let nonSchoolDay = CDNonSchoolDay(context: context)
                nonSchoolDay.date = day
                isNowNonSchool = true
            }
            // Save is handled by caller or autosave - no immediate save needed
            invalidateMonthCache(for: day)
            Self.notifySchoolDayDataChanged()
            return isNowNonSchool
        }
    }

    /// Returns the next school day strictly after the given date.
    /// Weekends and configured non-school days are skipped; weekend overrides are respected.
    public func nextSchoolDay(after date: Date, using context: NSManagedObjectContext) async -> Date {
        nextSchoolDaySync(after: date, using: context)
    }

    /// Returns the previous school day strictly before the given date.
    /// Weekends and configured non-school days are skipped; weekend overrides are respected.
    public func previousSchoolDay(before date: Date, using context: NSManagedObjectContext) async -> Date {
        previousSchoolDaySync(before: date, using: context)
    }

    /// Coerces the provided date to the nearest school day.
    /// If the date is already a school day, it is returned unchanged.
    /// Otherwise, the closer of the previous/next school day is chosen
    /// (ties prefer the next day).
    public func nearestSchoolDay(to date: Date, using context: NSManagedObjectContext) async -> Date {
        nearestSchoolDaySync(to: date, using: context)
    }
}

// MARK: - Change Notification

extension Notification.Name {
    /// Posted when school-day data (explicit non-school days or weekend
    /// overrides) changes — via a local edit or a CloudKit sync. Observers
    /// invalidate any cached school-day calculations. See
    /// `AppDependencies.invalidateSchoolDayCaches()`.
    static let schoolDayDataDidChange = Notification.Name("schoolDayDataDidChange")
}

/// Monotonic version stamp, bumped whenever school-day data changes.
/// `SchoolCalendarService` compares it lazily on each lookup so a stale cache
/// is dropped even if the change notification has not been delivered yet, and
/// views key their school-day `.task` work on it so they recompute only when
/// the day or the calendar data actually changes.
///
/// Thread-safe and nonisolated so it can be read from any context.
enum SchoolDayDataVersion {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current = 0

    static var current: Int {
        lock.lock(); defer { lock.unlock() }
        return _current
    }

    static func bump() {
        lock.lock(); defer { lock.unlock() }
        _current += 1
    }
}
