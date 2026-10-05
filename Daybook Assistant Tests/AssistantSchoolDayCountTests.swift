import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// "Day 37": the school year's first day, worked out from the marks, and the
// count from there by the guide's calendar. 2026-08-31 is a Monday.
@Suite("Assistant school-day count")
@MainActor
struct AssistantSchoolDayCountTests {

    typealias Count = AttendanceSchoolDayCount

    private func day(_ iso: String) throws -> Date {
        try AssistantTestSupport.day(iso)
    }

    private func mark(
        _ student: CDStudent,
        _ status: AttendanceStatus,
        on iso: String,
        in context: NSManagedObjectContext
    ) throws {
        let record = CDAttendanceRecord(context: context)
        record.studentID = student.id?.uuidString ?? ""
        record.date = try day(iso)
        record.status = status
    }

    @Test("The year's first day is looked for from July 1")
    func yearStart() throws {
        #expect(Count.yearStart(for: try day("2026-08-31")) == (try day("2026-07-01")))
        #expect(Count.yearStart(for: try day("2027-03-01")) == (try day("2026-07-01")))
        #expect(Count.yearStart(for: try day("2026-06-30")) == (try day("2025-07-01")))
    }

    @Test("The first day is the first child marked here since July 1, not an absence marked ahead")
    func firstDay() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        try mark(maya, .present, on: "2026-06-15", in: context)   // last year
        try mark(ari, .absent, on: "2026-08-20", in: context)     // a vacation marked ahead
        try mark(maya, .tardy, on: "2026-08-31", in: context)
        try mark(ari, .present, on: "2026-09-01", in: context)
        #expect(context.safeSave())

        #expect(Count.firstDay(inYearStarting: try day("2026-07-01"), in: context) == (try day("2026-08-31")))
        #expect(Count.firstDay(inYearStarting: try day("2025-07-01"), in: context) == (try day("2026-06-15")))
        #expect(Count.firstDay(inYearStarting: try day("2027-07-01"), in: context) == nil)
    }

    @Test("The count skips weekends and days off")
    func countSkipsDaysOff() throws {
        let first = try day("2026-08-31")
        let daysOff: Set<Date> = [try day("2026-09-05"), try day("2026-09-06"), try day("2026-09-07")]
        #expect(Count.number(of: first, firstDay: first, nonSchoolDays: daysOff) == 1)
        #expect(Count.number(of: try day("2026-09-04"), firstDay: first, nonSchoolDays: daysOff) == 5)
        #expect(Count.number(of: try day("2026-09-08"), firstDay: first, nonSchoolDays: daysOff) == 6)
    }

    @Test("No number before the first day, or on a day off")
    func noNumber() throws {
        let first = try day("2026-08-31")
        let daysOff: Set<Date> = [try day("2026-09-05")]
        #expect(Count.number(of: try day("2026-08-28"), firstDay: first, nonSchoolDays: daysOff) == nil)
        #expect(Count.number(of: try day("2026-09-05"), firstDay: first, nonSchoolDays: daysOff) == nil)
    }

    @Test("The store's calendar counts: a holiday is skipped, a school Saturday counts")
    func countFromStore() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let holiday = CDNonSchoolDay(context: context)
        holiday.date = try day("2026-09-07")
        holiday.reason = "Labor Day"
        let saturday = CDSchoolDayOverride(context: context)
        saturday.date = try day("2026-09-12")
        #expect(context.safeSave())

        let first = try day("2026-08-31")
        // Aug 31–Sep 4 (5), Sep 8–11 (4), Saturday Sep 12, Monday Sep 14.
        #expect(Count.number(of: try day("2026-09-14"), firstDay: first, in: context) == 11)
        #expect(Count.number(of: try day("2026-09-07"), firstDay: first, in: context) == nil)
    }

    @Test("Milestones fall on the first and hundredth days")
    func milestones() {
        #expect(Count.milestone(for: 1) == .firstDay)
        #expect(Count.milestone(for: 100) == .hundredthDay)
        #expect(Count.milestone(for: 37) == nil)
        #expect(Count.milestone(for: nil) == nil)
    }

    @Test("The grid shows the day's number, and none on a weekend")
    func gridDayNumber() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        try mark(maya, .present, on: "2026-08-31", in: context)
        #expect(context.safeSave())

        let model = AssistantTestSupport.viewModel(stack, on: try day("2026-09-03"))
        #expect(model.dayNumber == 4)
        #expect(model.milestone == nil)

        model.load(try day("2026-09-05"))
        #expect(model.dayNumber == nil)

        model.load(try day("2026-08-31"))
        #expect(model.dayNumber == 1)
        #expect(model.milestone == .firstDay)
    }

    @Test("A first day that syncs in later is picked up on the next load")
    func firstDayArrivesLater() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        #expect(context.safeSave())

        let model = AssistantTestSupport.viewModel(stack, on: try day("2026-09-03"))
        #expect(model.dayNumber == nil)

        try mark(maya, .present, on: "2026-08-31", in: context)
        #expect(context.safeSave())
        model.load()
        #expect(model.dayNumber == 4)
    }

    // Bug hunt 2026-10-04, step 11: a first day found among a first
    // download's early pieces stood for good, so the number stayed short.
    @Test("An earlier first day that syncs in later moves the day number")
    func earlierFirstDayArrivesLater() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        try mark(maya, .present, on: "2026-09-02", in: context)
        #expect(context.safeSave())

        let model = AssistantTestSupport.viewModel(stack, on: try day("2026-09-03"))
        #expect(model.dayNumber == 2)

        try mark(maya, .present, on: "2026-08-31", in: context)
        #expect(context.safeSave())
        model.load()
        #expect(model.dayNumber == 4)
    }
}
