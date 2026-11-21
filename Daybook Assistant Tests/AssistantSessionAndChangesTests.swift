import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The Assistant reads the school session and "changed since reported" from
// the classroom share, as the notebook does (domain-logic review R20, R18,
// A1): summer is a day off with its own reason, the front-desk line says
// when marks changed after the email went, and an arrival-closed note is no
// send.
@Suite("Assistant school session and changes since reported")
@MainActor
struct AssistantSessionAndChangesTests {

    typealias Model = AssistantAttendanceViewModel

    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(AppCalendar.shared.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private func at(_ hour: Int, _ minute: Int, on day: Date) throws -> Date {
        try #require(AppCalendar.shared.date(bySettingHour: hour, minute: minute, second: 0, of: day))
    }

    private static let settings = AttendanceEmailLog.Settings(
        isEnabled: true, toAddresses: "office@school.org", nameOrder: .firstLast, groupByLevel: false
    )

    /// The guide's session, August 25, 2026 to June 18, 2027, as it arrives in the share.
    private func setSession(in ctx: NSManagedObjectContext) throws {
        let session = try #require(SchoolSession(firstDay: try day(2026, 8, 25), lastDay: try day(2027, 6, 18)))
        let written = AttendanceEmailLog.saveClassroomCalendar(
            timeZoneID: nil, session: session, base: Self.settings, role: .leadGuide, in: ctx
        )
        #expect(written)
    }

    @Test("A summer weekday is a day off once the guide sets the session: Summer break")
    func summerIsADayOff() throws {
        let stack = try AssistantTestSupport.makeStack()
        let ctx = stack.viewContext
        AssistantTestSupport.student("Maya", "Stone", in: ctx)
        let july15 = try day(2027, 7, 15)
        try #require((2...6).contains(AppCalendar.shared.component(.weekday, from: july15)))
        let week = try day(2027, 7, 12)..<(try day(2027, 7, 17))

        #expect(Model.dayOff(on: july15, in: ctx) == nil)
        #expect(SiriHost.isSchoolDay(july15, in: ctx))
        #expect(AttendanceEmailLog.nonSchoolDays(in: week, using: ctx).isEmpty)

        try setSession(in: ctx)
        #expect(Model.dayOff(on: july15, in: ctx) == .holiday(Model.summerBreak))
        #expect(!SiriHost.isSchoolDay(july15, in: ctx))
        // What the arrival and front-desk reminders skip.
        #expect(AttendanceEmailLog.nonSchoolDays(in: week, using: ctx).count == 5)
        #expect(AssistantTestSupport.viewModel(stack, on: july15).dayOff == .holiday(Model.summerBreak))

        // A school day in session is still one, and so is last year's.
        #expect(Model.dayOff(on: try day(2027, 1, 12), in: ctx) == nil)
        #expect(Model.dayOff(on: try day(2026, 3, 10), in: ctx) == nil)
        // The ‹ › arrows step over the summer to the next first day.
        let next = SchoolDayChecker.schoolDay(from: try day(2027, 6, 18), forward: true, using: ctx)
        #expect(try next == day(2027, 8, 25))
    }

    @Test("A mark changed after the email went shows on the front-desk line")
    func changesSinceTheEmail() throws {
        let stack = try AssistantTestSupport.makeStack()
        let ctx = stack.viewContext
        AssistantTestSupport.student("Maya", "Stone", in: ctx)
        let tuesday = try day(2026, 11, 17)
        let sentAt = try at(9, 2, on: tuesday)
        AttendanceEmailLog.recordSend(on: tuesday, role: .leadGuide, now: sentAt, in: ctx)

        let model = AssistantTestSupport.viewModel(stack, on: tuesday)
        #expect(model.frontDesk.latestSend?.sentAt == sentAt)
        #expect(model.frontDesk.changes == nil)

        // Maya comes in late, long after 9:02.
        let maya = try #require(model.rows.first { $0.student.firstName == "Maya" })
        model.setStatus(.tardy, for: maya)
        let changes = try #require(model.frontDesk.changes)
        #expect(changes.count == 1)
        let time = AttendanceEmailLog.Send.time(sentAt, reporting: tuesday)
        #expect(changes.line(for: tuesday) == "1 change since \(time) · Send an update")

        // A reload reads the same, and another day has none.
        model.load()
        #expect(model.frontDesk.changes?.count == 1)
        #expect(AttendanceEmailLog.changesSinceReported(on: try day(2026, 11, 18), in: ctx) == nil)
    }

    @Test("An arrival-closed note isn't the day's send")
    func arrivalClosedNoteIsNoSend() throws {
        let stack = try AssistantTestSupport.makeStack()
        let ctx = stack.viewContext
        AssistantTestSupport.student("Maya", "Stone", in: ctx)
        let tuesday = try day(2026, 11, 17)
        let note = CDAttendanceEmailSend(context: ctx)
        note.date = tuesday
        note.sentAt = try at(9, 0, on: tuesday)
        note.channelRaw = AttendanceEmailLog.arrivalClosedChannel

        let model = AssistantTestSupport.viewModel(stack, on: tuesday)
        #expect(model.frontDesk.latestSend == nil)
        #expect(model.frontDesk.daySends == nil)
        #expect(AttendanceEmailLog.arrivalClosedAt(on: tuesday, in: ctx) == note.sentAt)
    }
}
