import Foundation
import CoreData
import OSLog

/// An actor-backed calendar service that computes and caches non-school days,
/// ensuring thread safety and correct isolation for Core Data operations.
/// Converted to @MainActor to align with NSManagedObjectContext thread requirements in Swift 6.
@MainActor
public final class SchoolCalendarService {
    private static let logger = Logger.calendar_
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
    public func precomputedNonSchoolSet(in range: Range<Date>, using context: NSManagedObjectContext) async -> Set<Date> {
        let start = cal.startOfDay(for: range.lowerBound)
        let end = cal.startOfDay(for: range.upperBound)

        // Fetch Core Data models directly (we are on MainActor)
        let nsFetchRequest: NSFetchRequest<CDNonSchoolDay> = CDNonSchoolDay.fetchRequest() as! NSFetchRequest<CDNonSchoolDay>
        nsFetchRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        let ovFetchRequest: NSFetchRequest<CDSchoolDayOverride> = CDSchoolDayOverride.fetchRequest() as! NSFetchRequest<CDSchoolDayOverride>
        ovFetchRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        let ns: [CDNonSchoolDay]
        let ovs: [CDSchoolDayOverride]
        do {
            ns = try context.fetch(nsFetchRequest)
        } catch {
            Self.logger.warning("Failed to fetch non-school days: \(error)")
            ns = []
        }
        do {
            ovs = try context.fetch(ovFetchRequest)
        } catch {
            Self.logger.warning("Failed to fetch school day overrides: \(error)")
            ovs = []
        }
        
        let nonSchoolDates = ns.map { $0.date ?? .distantPast }
        let overrideDates = ovs.map { $0.date ?? .distantPast }

        var result = Set<Date>(nonSchoolDates.map { cal.startOfDay(for: $0) })

        // Add weekends in range by default
        var d = start
        while d < end {
            let wd = cal.component(.weekday, from: d)
            if wd == 1 || wd == 7 { // Sunday or Saturday
                result.insert(d)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }

        // Remove weekend overrides (weekend becomes a school day)
        for ovDate in overrideDates {
            result.remove(cal.startOfDay(for: ovDate))
        }
        return result
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
            let overrideFetch: NSFetchRequest<CDSchoolDayOverride> = CDSchoolDayOverride.fetchRequest() as! NSFetchRequest<CDSchoolDayOverride>
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
            return becameNonSchool
        } else {
            // Weekday logic
            let nsFetch: NSFetchRequest<CDNonSchoolDay> = CDNonSchoolDay.fetchRequest() as! NSFetchRequest<CDNonSchoolDay>
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
