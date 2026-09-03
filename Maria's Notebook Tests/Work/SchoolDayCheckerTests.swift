import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

/// Boundary tests for `SchoolDayChecker`, which feeds work aging and
/// agenda/attendance day math. Uses fixed June 2026 dates so results never
/// depend on when the suite runs.
@Suite("School Day Rules")
@MainActor
final class SchoolDayCheckerTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        let date = AppCalendar.shared.date(from: components)!
        return AppCalendar.startOfDay(date)
    }

    // June 2026: the 8th is a Monday, the 13th/14th a weekend.
    private var monday: Date { day(2026, 6, 8) }
    private var wednesday: Date { day(2026, 6, 10) }
    private var friday: Date { day(2026, 6, 12) }
    private var saturday: Date { day(2026, 6, 13) }
    private var sunday: Date { day(2026, 6, 14) }
    private var nextMonday: Date { day(2026, 6, 15) }
    private var nextTuesday: Date { day(2026, 6, 16) }

    @Test("Weekdays default to school days")
    func weekdayDefault() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        #expect(SchoolDayChecker.isSchoolDay(monday, using: ctx))
        #expect(SchoolDayChecker.isSchoolDay(friday, using: ctx))
    }

    @Test("Weekends default to non-school days")
    func weekendDefault() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        #expect(!SchoolDayChecker.isSchoolDay(saturday, using: ctx))
        #expect(!SchoolDayChecker.isSchoolDay(sunday, using: ctx))
    }

    @Test("A NonSchoolDay record turns a weekday into a non-school day")
    func nonSchoolDayRecord() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let holiday = CDNonSchoolDay(context: ctx)
        holiday.date = monday
        #expect(CoreDataTestHelpers.save(ctx))

        #expect(!SchoolDayChecker.isSchoolDay(monday, using: ctx))
        // Other weekdays are unaffected.
        #expect(SchoolDayChecker.isSchoolDay(wednesday, using: ctx))
    }

    @Test("A SchoolDayOverride makes a weekend count as a school day")
    func weekendOverride() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let makeup = CDSchoolDayOverride(context: ctx)
        makeup.date = saturday
        #expect(CoreDataTestHelpers.save(ctx))

        #expect(SchoolDayChecker.isSchoolDay(saturday, using: ctx))
        #expect(!SchoolDayChecker.isSchoolDay(sunday, using: ctx))
    }

    @Test("An explicit NonSchoolDay beats a SchoolDayOverride on the same date")
    func nonSchoolDayPrecedence() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let holiday = CDNonSchoolDay(context: ctx)
        holiday.date = saturday
        let makeup = CDSchoolDayOverride(context: ctx)
        makeup.date = saturday
        #expect(CoreDataTestHelpers.save(ctx))

        #expect(!SchoolDayChecker.isSchoolDay(saturday, using: ctx))
    }

    @Test("isSchoolDay and isNonSchoolDay stay exact inverses")
    func inverseConsistency() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let holiday = CDNonSchoolDay(context: ctx)
        holiday.date = wednesday
        #expect(CoreDataTestHelpers.save(ctx))

        for sample in [monday, wednesday, friday, saturday, sunday] {
            #expect(
                SchoolDayChecker.isSchoolDay(sample, using: ctx)
                    == !SchoolDayChecker.isNonSchoolDay(sample, using: ctx)
            )
        }
    }

    @Test("schoolDaysBetween is exclusive of the end date and skips weekends")
    func schoolDaysBetweenCounts() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext

        // Mon→Fri counts Mon, Tue, Wed, Thu.
        #expect(SchoolDayChecker.schoolDaysBetween(start: monday, end: friday, using: ctx) == 4)
        // Mon→next Mon spans the weekend: Mon–Fri only.
        #expect(SchoolDayChecker.schoolDaysBetween(start: monday, end: nextMonday, using: ctx) == 5)
        // Empty and inverted ranges count zero.
        #expect(SchoolDayChecker.schoolDaysBetween(start: monday, end: monday, using: ctx) == 0)
        #expect(SchoolDayChecker.schoolDaysBetween(start: friday, end: monday, using: ctx) == 0)
    }

    @Test("schoolDaysBetween skips NonSchoolDay records inside the range")
    func schoolDaysBetweenSkipsHolidays() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let holiday = CDNonSchoolDay(context: ctx)
        holiday.date = wednesday
        #expect(CoreDataTestHelpers.save(ctx))

        #expect(SchoolDayChecker.schoolDaysBetween(start: monday, end: friday, using: ctx) == 3)
    }

    @Test("nextSchoolDays skips the weekend and returns exactly the requested count")
    func nextSchoolDaysSkipsWeekend() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext

        let result = SchoolDayChecker.nextSchoolDays(from: friday, count: 3, using: ctx)
        #expect(result == [friday, nextMonday, nextTuesday])
    }

    // MARK: - Bulk/per-day consistency

    @Test("nonSchoolDaySet matches the per-day rule for every day in range")
    func bulkSetMatchesPerDayRule() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let holiday = CDNonSchoolDay(context: ctx)
        holiday.date = wednesday
        let makeup = CDSchoolDayOverride(context: ctx)
        makeup.date = saturday
        #expect(CoreDataTestHelpers.save(ctx))

        let rangeEnd = day(2026, 6, 22)
        let bulk = SchoolDayChecker.nonSchoolDaySet(in: monday..<rangeEnd, using: ctx)

        var cursor = monday
        while cursor < rangeEnd {
            #expect(
                bulk.contains(cursor) == SchoolDayChecker.isNonSchoolDay(cursor, using: ctx),
                "Bulk and per-day rule disagree on \(cursor)"
            )
            cursor = AppCalendar.addingDays(1, to: cursor)
        }
    }

    @Test("SchoolCalendarService agrees with SchoolDayChecker, including record-plus-override dates")
    func calendarServiceAgreesWithChecker() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        // Both a NonSchoolDay record and an override on the same Saturday —
        // the explicit record must win everywhere.
        let holiday = CDNonSchoolDay(context: ctx)
        holiday.date = saturday
        let makeup = CDSchoolDayOverride(context: ctx)
        makeup.date = saturday
        #expect(CoreDataTestHelpers.save(ctx))

        let serviceSet = await SchoolCalendarService.shared.precomputedNonSchoolSet(
            in: monday..<nextMonday,
            using: ctx
        )
        #expect(serviceSet.contains(saturday))
        #expect(!SchoolDayChecker.isSchoolDay(saturday, using: ctx))
    }

    @Test("SchoolCalendarService's cached lookups and counts agree with SchoolDayChecker")
    func calendarServiceCacheAgreesWithChecker() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let holiday = CDNonSchoolDay(context: ctx)
        holiday.date = wednesday
        let makeup = CDSchoolDayOverride(context: ctx)
        makeup.date = saturday
        #expect(CoreDataTestHelpers.save(ctx))

        let service = SchoolCalendarService.shared
        service.invalidateCache()
        defer { service.invalidateCache() }

        // Mon, Tue, Thu, Fri, Sat (make-up day), next Mon — the Wednesday holiday and Sunday are skipped.
        #expect(SchoolDayChecker.schoolDaysBetween(start: monday, end: nextTuesday, using: ctx) == 6)
        #expect(service.schoolDaysBetween(start: monday, end: nextTuesday, using: ctx) == 6)
        // Second call is served from the memo and must agree with the first.
        #expect(service.schoolDaysBetween(start: monday, end: nextTuesday, using: ctx) == 6)

        #expect(service.isNonSchoolDaySync(wednesday, using: ctx))
        #expect(!service.isNonSchoolDaySync(saturday, using: ctx))
        #expect(service.isNonSchoolDaySync(sunday, using: ctx))
        #expect(service.nextSchoolDaySync(after: friday, using: ctx) == saturday)
        #expect(service.previousSchoolDaySync(before: nextMonday, using: ctx) == saturday)
        #expect(service.nearestSchoolDaySync(to: sunday, using: ctx) == nextMonday)
    }
}
