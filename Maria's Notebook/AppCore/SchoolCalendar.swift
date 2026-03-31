import Foundation
import CoreData

@MainActor
struct SchoolCalendar {
    /// Returns true if the given date is a non-school day
    /// (weekend or configured non-school date), taking overrides into account.
    static func isNonSchoolDay(_ date: Date, using context: NSManagedObjectContext) async -> Bool {
        await SchoolCalendarService.shared.isNonSchoolDay(date, using: context)
    }

    /// Returns a precomputed set of non-school days in the given range.
    static func precomputedNonSchoolSet(in range: Range<Date>, using context: NSManagedObjectContext) async -> Set<Date> {
        await SchoolCalendarService.shared.precomputedNonSchoolSet(in: range, using: context)
    }

    /// Returns the set of non-school days in the given range.
    static func nonSchoolDays(in range: Range<Date>, using context: NSManagedObjectContext) async -> Set<Date> {
        await SchoolCalendarService.shared.nonSchoolDays(in: range, using: context)
    }

    /// Toggle the non-school state for a date.
    @discardableResult
    static func toggleNonSchoolDay(_ date: Date, using context: NSManagedObjectContext) async throws -> Bool {
        try await SchoolCalendarService.shared.toggleNonSchoolDay(date, using: context)
    }

    /// Returns the next school day strictly after the given date.
    static func nextSchoolDay(after date: Date, using context: NSManagedObjectContext) async -> Date {
        await SchoolCalendarService.shared.nextSchoolDay(after: date, using: context)
    }

    /// Returns the previous school day strictly before the given date.
    static func previousSchoolDay(before date: Date, using context: NSManagedObjectContext) async -> Date {
        await SchoolCalendarService.shared.previousSchoolDay(before: date, using: context)
    }

    /// Coerces the provided date to the nearest school day.
    static func nearestSchoolDay(to date: Date, using context: NSManagedObjectContext) async -> Date {
        await SchoolCalendarService.shared.nearestSchoolDay(to: date, using: context)
    }
}
