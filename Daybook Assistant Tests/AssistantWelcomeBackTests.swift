import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// A child back after three or more school days away. 2026-09-28 is a Monday.
@Suite("Assistant welcome back")
@MainActor
struct AssistantWelcomeBackTests {

    typealias Welcome = AssistantWelcomeBack

    private func day(_ iso: String) throws -> Date {
        try AssistantTestSupport.day(iso)
    }

    private func mark(
        _ student: CDStudent,
        _ status: AttendanceStatus,
        on isos: [String],
        in context: NSManagedObjectContext
    ) throws {
        for iso in isos {
            let record = CDAttendanceRecord(context: context)
            record.studentID = student.id?.uuidString ?? ""
            record.date = try day(iso)
            record.status = status
        }
    }

    @Test("Days away counts absences back from the day before, until anything else")
    func daysAway() {
        #expect(Welcome.daysAway(statuses: [.absent, .absent, .absent]) == 3)
        #expect(Welcome.daysAway(statuses: [.absent, .absent, .present, .absent]) == 2)
        #expect(Welcome.daysAway(statuses: [.absent, .tardy, .absent]) == 1)
        #expect(Welcome.daysAway(statuses: [nil, .absent, .absent]) == 0)
        #expect(Welcome.daysAway(statuses: []) == 0)
    }

    @Test("Three school days away is a welcome; two isn't; a weekend doesn't count")
    func threshold() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        try mark(maya, .absent, on: ["2026-09-23", "2026-09-24", "2026-09-25"], in: context)
        try mark(ari, .present, on: ["2026-09-23"], in: context)
        try mark(ari, .absent, on: ["2026-09-24", "2026-09-25"], in: context)
        #expect(context.safeSave())

        let returning = Welcome.returning(on: try day("2026-09-28"), in: context)
        #expect(returning == [try #require(maya.id?.uuidString): 3])
    }

    @Test("A holiday between absences doesn't end the run")
    func holidayInside() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let holiday = CDNonSchoolDay(context: context)
        holiday.date = try day("2026-09-25")
        try mark(maya, .absent, on: ["2026-09-22", "2026-09-23", "2026-09-24"], in: context)
        #expect(context.safeSave())

        let returning = Welcome.returning(on: try day("2026-09-28"), in: context)
        #expect(returning[try #require(maya.id?.uuidString)] == 3)
    }

    @Test("A school day with no mark ends the run")
    func unmarkedDayEndsRun() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        try mark(maya, .absent, on: ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-25"], in: context)
        #expect(context.safeSave())

        #expect(Welcome.returning(on: try day("2026-09-28"), in: context).isEmpty)
    }

    @Test("A long absence stops counting at the lookback")
    func longAbsence() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let calendar = Calendar.current
        let monday = try day("2026-09-28")
        for offset in 1...30 {
            let date = try #require(calendar.date(byAdding: .day, value: -offset, to: monday))
            let weekday = calendar.component(.weekday, from: date)
            guard weekday != 1, weekday != 7 else { continue }
            let record = CDAttendanceRecord(context: context)
            record.studentID = maya.id?.uuidString ?? ""
            record.date = date
            record.status = .absent
        }
        #expect(context.safeSave())

        #expect(Welcome.returning(on: monday, in: context)[try #require(maya.id?.uuidString)] == Welcome.lookback)
        #expect(Welcome.phrase(daysAway: Welcome.lookback) == "Back after 15+ days")
        #expect(Welcome.phrase(daysAway: 4) == "Back after 4 days")
    }

    @Test("The grid carries it to the row, and her mark welcomes only the returning child")
    func gridWelcome() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        try mark(maya, .absent, on: ["2026-09-23", "2026-09-24", "2026-09-25"], in: context)
        #expect(context.safeSave())

        let model = AssistantTestSupport.viewModel(stack, on: try day("2026-09-28"))
        let mayaRow = try #require(model.rows.first { $0.name == "Maya Stone" })
        let ariRow = try #require(model.rows.first { $0.name == "Ari Cedar" })
        #expect(mayaRow.daysAway == 3)
        #expect(ariRow.daysAway == nil)

        model.tap(ariRow)
        #expect(model.welcome == nil)

        model.tap(mayaRow)
        #expect(model.welcome?.name == "Maya")
        let first = model.welcome
        // Still marked away after the tap re-renders the row.
        #expect(model.rows.first { $0.name == "Maya Stone" }?.daysAway == 3)

        // Unmarking and marking again welcomes again.
        let marked = try #require(model.rows.first { $0.name == "Maya Stone" })
        model.tap(marked)
        let cleared = try #require(model.rows.first { $0.name == "Maya Stone" })
        model.tap(cleared)
        #expect(model.welcome != first)
    }
}
