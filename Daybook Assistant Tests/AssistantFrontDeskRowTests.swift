import Foundation
import Testing
@testable import Daybook_Assistant

// The front-desk line in the bottom bar redraws itself only at the moments it
// changes (the due window opening, and the due time), and waits for nothing
// once they have passed: an explicit TimelineView whose moments had all
// passed redrew the bar every frame (2026-10-10).
@Suite("Assistant front-desk line redraws")
@MainActor
struct AssistantFrontDeskRowTests {

    private let calendar = Calendar.current
    private var day: Date { calendar.startOfDay(for: Date()) }
    /// As `AttendanceEmailLog.urgency` and `AssistantFrontDesk.changeTimes` work it out.
    private var deadline: Date {
        calendar.date(byAdding: .minute, value: AttendanceEmailLog.defaultDeadlineMinutes, to: day) ?? day
    }
    private var dueFrom: Date { deadline.addingTimeInterval(-Double(AttendanceEmailLog.dueWindowMinutes) * 60) }
    private var times: [Date] { [dueFrom, deadline] }

    private func urgency(at now: Date) -> AttendanceEmailLog.Urgency {
        AttendanceEmailLog.urgency(for: day, deadlineMinutes: AttendanceEmailLog.defaultDeadlineMinutes, now: now)
    }

    @Test("Before the due window, it waits for both moments, and the line changes at each")
    func beforeTheWindow() {
        let now = dueFrom.addingTimeInterval(-3600)
        #expect(AssistantFrontDeskRow.changesAhead(times, now: now) == [dueFrom, deadline])
        #expect(urgency(at: now) == .none)
        #expect(urgency(at: dueFrom) == .due(deadline))
        #expect(urgency(at: deadline) == .overdue(deadline))
    }

    @Test("Inside the due window, it waits only for the due time")
    func insideTheWindow() {
        let now = dueFrom.addingTimeInterval(60)
        #expect(AssistantFrontDeskRow.changesAhead(times, now: now) == [deadline])
    }

    @Test("At and after the due time, and on a past day, it waits for nothing")
    func afterTheDueTime() {
        #expect(AssistantFrontDeskRow.changesAhead(times, now: deadline).isEmpty)
        #expect(AssistantFrontDeskRow.changesAhead(times, now: deadline.addingTimeInterval(3600)).isEmpty)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? deadline.addingTimeInterval(86_400)
        #expect(AssistantFrontDeskRow.changesAhead(times, now: nextDay).isEmpty)
    }
}
