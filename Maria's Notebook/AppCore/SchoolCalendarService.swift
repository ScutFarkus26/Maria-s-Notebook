import Foundation
import CoreData
import OSLog

/// An actor-backed calendar service that computes and caches non-school days,
/// ensuring thread safety and correct isolation for Core Data operations.
/// Converted to @MainActor to align with NSManagedObjectContext thread requirements in Swift 6.
@MainActor
public final class SchoolCalendarService {
    public static let shared = SchoolCalendarService()

    // MARK: - State

    // Cache keyed by start-of-month date -> set of non-school start-of-day dates within that month.
    private var monthSets: [Date: Set<Date>] = [:]

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
        let key = monthKey(for: date)
        monthSets.removeValue(forKey: key)
    }

    /// Clears the entire month cache. Use when school-day data may have changed
    /// in bulk (a CloudKit sync or a restore) rather than at a single known date.
    public func invalidateCache() {
        monthSets.removeAll()
    }

    /// Announces that school-day data changed so cached school-day calculations
    /// get invalidated. Call after any edit to non-school days / weekend overrides.
    static func notifySchoolDayDataChanged() {
        NotificationCenter.default.post(name: .schoolDayDataDidChange, object: nil)
    }

    private func setForMonth(_ date: Date, using context: NSManagedObjectContext) async -> Set<Date> {
        let key = monthKey(for: date)
        if let cached = monthSets[key] {
            return cached
        }
        let set = await precomputedNonSchoolSet(in: monthRange(containing: date), using: context)
        monthSets[key] = set
        return set
    }

    // MARK: - Public API

    /// Returns true if the given date is a non-school day (weekend or configured non-school date),
    /// taking weekend overrides into account.
    public func isNonSchoolDay(_ date: Date, using context: NSManagedObjectContext) async -> Bool {
        let day = cal.startOfDay(for: date)
        let set = await setForMonth(day, using: context)
        return set.contains(day)
    }

    /// Returns a precomputed set of non-school days in the given range.
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
        var d = cal.startOfDay(for: date)
        // Start from the following day
        d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        // Safety cap to avoid infinite loops in case of data errors
        for _ in 0..<730 { // up to ~2 years
            if !(await isNonSchoolDay(d, using: context)) { return d }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    /// Returns the previous school day strictly before the given date.
    /// Weekends and configured non-school days are skipped; weekend overrides are respected.
    public func previousSchoolDay(before date: Date, using context: NSManagedObjectContext) async -> Date {
        var d = cal.startOfDay(for: date)
        // Start from the previous day
        d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        for _ in 0..<730 { // up to ~2 years
            if !(await isNonSchoolDay(d, using: context)) { return d }
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    /// Coerces the provided date to the nearest school day.
    /// If the date is already a school day, it is returned unchanged.
    /// Otherwise, the closer of the previous/next school day is chosen
    /// (ties prefer the next day).
    public func nearestSchoolDay(to date: Date, using context: NSManagedObjectContext) async -> Date {
        let day = cal.startOfDay(for: date)
        if !(await isNonSchoolDay(day, using: context)) { return day }
        let prev = await previousSchoolDay(before: day, using: context)
        let next = await nextSchoolDay(after: day, using: context)
        let distPrev = abs(prev.timeIntervalSince(day))
        let distNext = abs(next.timeIntervalSince(day))
        if distPrev < distNext { return prev }
        // On tie or next closer, prefer next
        return next
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

/// Monotonic version stamp, bumped whenever school-day data changes. Lets
/// lightweight per-instance caches (e.g. `SchoolDayCache`) detect staleness
/// lazily on their next use, without each one registering a notification
/// observer (which would accumulate for short-lived instances).
///
/// Thread-safe and nonisolated so caches can read it from any context —
/// including non-MainActor callers such as `TodayNavigationService`.
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
