import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The Daybook Assistant's ‹ › arrows: step to the next or previous school day,
/// over weekends and the guide's days off, in either direction.
@Suite("School day stepping")
@MainActor
struct SchoolDaySteppingTests {

    private func day(_ month: Int, _ dayOfMonth: Int) -> Date {
        let components = DateComponents(year: 2026, month: month, day: dayOfMonth)
        return AppCalendar.startOfDay(AppCalendar.shared.date(from: components)!)
    }

    @Test("Friday steps forward to Monday, Monday back to Friday")
    func stepsOverWeekends() throws {
        let ctx = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        // June 2026: the 12th is a Friday, the 15th a Monday.
        #expect(SchoolDayChecker.schoolDay(from: day(6, 12), forward: true, using: ctx) == day(6, 15))
        #expect(SchoolDayChecker.schoolDay(from: day(6, 15), forward: false, using: ctx) == day(6, 12))
        // From a weekend day, either way lands on the nearest school day.
        #expect(SchoolDayChecker.schoolDay(from: day(6, 13), forward: true, using: ctx) == day(6, 15))
        #expect(SchoolDayChecker.schoolDay(from: day(6, 13), forward: false, using: ctx) == day(6, 12))
    }

    @Test("Days off on the school calendar are skipped")
    func stepsOverDaysOff() throws {
        let ctx = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        // The school break: Monday 28 Sep – Friday 9 Oct 2026, back Monday 12 Oct.
        var off = day(9, 28)
        while off <= day(10, 9) {
            let holiday = CDNonSchoolDay(context: ctx)
            holiday.date = off
            holiday.reason = "Break"
            off = AppCalendar.shared.date(byAdding: .day, value: 1, to: off)!
        }
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(SchoolDayChecker.schoolDay(from: day(9, 25), forward: true, using: ctx) == day(10, 12))
        #expect(SchoolDayChecker.schoolDay(from: day(10, 12), forward: false, using: ctx) == day(9, 25))
    }
}
