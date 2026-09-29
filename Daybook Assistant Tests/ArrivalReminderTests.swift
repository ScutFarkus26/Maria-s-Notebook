import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The arrival reminder fires at the set time on school days only, never in the
// past, and not today once everyone's marked.
@Suite("Arrival reminder")
@MainActor
struct ArrivalReminderTests {

    private let calendar = AppCalendar.shared

    private func day(_ iso: String) throws -> Date {
        try AssistantTestSupport.day(iso)
    }

    @Test("School days only, at the set time, starting today when it's still ahead")
    func schoolDaysAtTheSetTime() throws {
        // Tuesday 2026-09-29, 7:00. Days off: the weekend and Thursday.
        let now = try day("2026-09-29").addingTimeInterval(7 * 3600)
        let off: Set<Date> = try Set(["2026-10-01", "2026-10-03", "2026-10-04"].map(day))

        let dates = ArrivalReminder.fireDates(
            from: now, minutes: 8 * 60 + 15, nonSchoolDays: off, count: 4, todayIsDone: false, calendar: calendar
        )

        let expected = try ["2026-09-29", "2026-09-30", "2026-10-02", "2026-10-05"].map {
            try day($0).addingTimeInterval(8 * 3600 + 15 * 60)
        }
        #expect(dates == expected)
    }

    @Test("Past today's time, or with today done, it starts tomorrow")
    func skipsToday() throws {
        let tuesday = try day("2026-09-29")
        let afterTime = tuesday.addingTimeInterval(9 * 3600)
        let early = tuesday.addingTimeInterval(7 * 3600)
        let wednesday = try day("2026-09-30").addingTimeInterval(8 * 3600 + 15 * 60)

        let late = ArrivalReminder.fireDates(
            from: afterTime, minutes: 495, nonSchoolDays: [], count: 1, todayIsDone: false, calendar: calendar
        )
        #expect(late == [wednesday])

        let done = ArrivalReminder.fireDates(
            from: early, minutes: 495, nonSchoolDays: [], count: 1, todayIsDone: true, calendar: calendar
        )
        #expect(done == [wednesday])
    }

    @Test("The roll is complete only when everyone on it has a mark")
    func rollComplete() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        _ = context.safeSave()
        let today = calendar.startOfDay(for: Date())
        #expect(!ArrivalReminder.isRollComplete(on: today, in: context))

        let model = AssistantTestSupport.viewModel(stack)
        let ari = try #require(model.rows.first { $0.student.firstName == "Ari" })
        model.tap(ari)
        #expect(!ArrivalReminder.isRollComplete(on: today, in: context))

        #expect(model.beginLate() == 1)
        #expect(ArrivalReminder.isRollComplete(on: today, in: context))
    }

    @Test("The sync line says 'just now' for the first minute")
    func relativeWording() {
        let now = Date()
        #expect(AssistantSyncStatusView.relative(now.addingTimeInterval(-20), now: now) == "just now")
        #expect(AssistantSyncStatusView.relative(now.addingTimeInterval(-300), now: now) != "just now")
    }
}
