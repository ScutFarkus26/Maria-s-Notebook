import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// How long a child has waited for a meeting (domain logic review
// 2026-11-20, R13 and A19): school days, as "due for a lesson" counts them;
// a meeting saved as not finished isn't a meeting met; and a child who has
// never met is late.
@Suite("Meeting queue cadence")
struct MeetingQueueCadenceTests {
    private let calendar = AppCalendar.shared

    /// November 2026: Friday 13, Monday 16, Monday 23.
    private func day(_ dayOfMonth: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: dayOfMonth, hour: hour))!
    }

    @Test("The cadence counts school days: nine calendar days over two weekends is within 7")
    func cadenceInSchoolDays() {
        let child = UUID()
        // Met Friday the 13th; on Sunday the 22nd, six school days have gone by.
        let signal = MeetingQueueSignals(lastMet: day(13), schoolDaysWaiting: 6)
        let result = MeetingQueueArrangement.arrange(
            ids: [child], signals: [child: signal], rules: MeetingQueueRules(cadenceDays: 7),
            now: day(22), calendar: calendar, epoch: nil
        )
        #expect(result.met == [child])
        #expect(!MeetingQueueArrangement.isLate(signal, cadenceDays: 7, now: day(22)))
    }

    @Test("Late is twice the cadence in school days")
    func lateInSchoolDays() {
        let late = MeetingQueueSignals(lastMet: day(1), schoolDaysWaiting: 14)
        let notYet = MeetingQueueSignals(lastMet: day(1), schoolDaysWaiting: 13)
        #expect(MeetingQueueArrangement.isLate(late, cadenceDays: 7, now: day(23)))
        #expect(!MeetingQueueArrangement.isLate(notYet, cadenceDays: 7, now: day(23)))
    }

    @Test("A meeting from before the school year's first day restarts the count but isn't met")
    func lastYearsMeetingIsNotMet() {
        let firstDay = day(2)
        let june = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        // The clamped count reads 2 school days, inside the cadence.
        let signal = MeetingQueueSignals(lastMet: june, schoolDaysWaiting: 2)
        #expect(!signal.hasMet(within: 7, now: day(4), calendar: calendar, epoch: firstDay))
        #expect(signal.hasMet(within: 7, now: day(4), calendar: calendar, epoch: nil))
        let thisYear = MeetingQueueSignals(lastMet: day(3), schoolDaysWaiting: 1)
        #expect(thisYear.hasMet(within: 7, now: day(4), calendar: calendar, epoch: firstDay))
    }

    @Test("A child who has never met counts as late")
    func neverMetIsLate() {
        #expect(MeetingQueueArrangement.isLate(MeetingQueueSignals(), cadenceDays: 7))
    }

    @Test("The queue counts school days from the store, and skips a meeting saved as not finished")
    @MainActor
    func queueCountsSchoolDaysAndFinishedMeetings() throws {
        // This week's Monday and the Friday before it, so the year-start
        // reset (which clamps to this school year) never moves the count.
        let today = AppCalendar.startOfDay(Date())
        let back = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = try #require(calendar.date(byAdding: .day, value: -back, to: today))
        let morning = try #require(calendar.date(byAdding: .hour, value: 10, to: monday))
        let friday = try #require(calendar.date(byAdding: .day, value: -3, to: morning))
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        let finished = CDStudentMeeting(context: context)
        finished.studentID = child.uuidString
        finished.date = friday
        finished.completed = true
        let unfinished = CDStudentMeeting(context: context)
        unfinished.studentID = child.uuidString
        unfinished.date = monday
        unfinished.completed = false
        #expect(CoreDataTestHelpers.save(context))

        let queue = MeetingQueueModel()
        queue.refreshIfNeeded(context: context, workOverdueDays: 14, now: morning)
        let signal = try #require(queue.signals[child])
        #expect(signal.lastMet == friday)
        // Friday to Monday: one school day, not three days.
        #expect(signal.schoolDaysWaiting == 1)
        #expect(signal.meetingIDs.count == 2)
    }
}
