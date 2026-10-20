import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// The notebook's side of the Daybook Assistant's 2026-10-20 bug hunt fixes
// (plan "Daybook Assistant bug hunt 2026-10-20 fixes", agent FD): the day's
// summary line names who sent it first and whether that was on time, with
// any later send as "sent again" (#15, read by the roll and MCP too), and
// Send to ParentLocker is prominent only for today, another day's Send Now
// asking first (#17).
@Suite("Attendance fixes 2026-10-20: front desk and ParentLocker")
@MainActor
struct AttendanceFix1020FD {

    typealias Screen = AttendanceExpandedView

    private static func at(_ hour: Int, _ minute: Int, on day: Date) -> Date {
        day.addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }

    private static func settings(_ method: AttendanceSendMethod) -> AttendanceEmailLog.Settings {
        AttendanceEmailLog.Settings(
            isEnabled: method == .email, toAddresses: "office@school.org", nameOrder: .firstLast,
            groupByLevel: false, deadlineMinutes: 540, sendMethod: method
        )
    }

    // MARK: - #15

    @Test("A second send doesn't relabel an on-time email late or change who sent it (#15)")
    func secondSendKeepsTheFirst() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let monday = try CoreDataTestHelpers.day("2026-10-12")
        AttendanceEmailLog.saveSettings(Self.settings(.email), role: .leadGuide, in: ctx)
        let first = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, now: Self.at(8, 42, on: monday), in: ctx
        )
        first.sentByID = "_sarah"
        first.sentByName = "Sarah"
        let again = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, now: Self.at(9, 15, on: monday), in: ctx
        )
        again.sentByID = "_ava"
        again.sentByName = "Ava"
        #expect(CoreDataTestHelpers.save(ctx))

        let onTime = AttendanceEmailLog.Send.time(Self.at(8, 42, on: monday), reporting: monday)
        let resent = AttendanceEmailLog.Send.time(Self.at(9, 15, on: monday), reporting: monday)
        #expect(AttendanceEmailLog.thirdPersonSummary(on: monday, in: ctx)
            == "Emailed \(onTime) by Sarah · sent again \(resent)")
        #expect(AttendanceEmailLog.latestSend(on: monday, in: ctx)?.sentByName == "Ava", "the newest still decides")
    }

    @Test("One send reads as it always did; a send the other way starts the line again (#15)")
    func oneSendAndAnotherWay() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let monday = try CoreDataTestHelpers.day("2026-10-12")
        AttendanceEmailLog.saveSettings(Self.settings(.parentLocker), role: .leadGuide, in: ctx)
        let email = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, now: Self.at(8, 42, on: monday), in: ctx
        )
        email.sentByName = "Sarah"
        #expect(CoreDataTestHelpers.save(ctx))
        let onTime = AttendanceEmailLog.Send.time(Self.at(8, 42, on: monday), reporting: monday)
        #expect(AttendanceEmailLog.thirdPersonSummary(on: monday, in: ctx) == "Emailed \(onTime) by Sarah")

        AttendanceEmailLog.recordSend(
            on: monday, role: .leadGuide, channel: .parentLocker, now: Self.at(9, 30, on: monday), in: ctx
        )
        #expect(CoreDataTestHelpers.save(ctx))
        let late = AttendanceEmailLog.Send.time(Self.at(9, 30, on: monday), reporting: monday)
        #expect(AttendanceEmailLog.thirdPersonSummary(on: monday, in: ctx)
            == "Sent to ParentLocker \(late) by the guide (late)")
    }

    // MARK: - #17

    @Test("The iPhone's row offers Send to ParentLocker only for today (#17)")
    func compactRowOnlyToday() {
        #expect(Screen.compactRowOffersSend(isOpen: true, isFuture: false, isRollComplete: true, isToday: true))
        #expect(!Screen.compactRowOffersSend(isOpen: true, isFuture: false, isRollComplete: true, isToday: false))
    }

    @Test("Another day's Send Now asks first, naming anyone unmarked (#17)")
    func otherDayQuestion() throws {
        let monday = try CoreDataTestHelpers.day("2026-10-12")
        let question = ParentLockerSendQuestion.otherDay(monday, unmarked: [])
        #expect(question.day == monday)
        #expect(question.title == ParentLockerStatus.otherDaySendTitle(for: monday))
        #expect(question.title.hasPrefix("Send Monday"))
        #expect(question.message == "This replaces what the office has for that day.")
        #expect(question.sendTitle == "Send")

        let waiting = ParentLockerSendQuestion.otherDay(monday, unmarked: ["Maya S", "Ari C"])
        #expect(waiting.message
            == "This replaces what the office has for that day. Maya S and Ari C aren't marked; the rest go.")
        #expect(ParentLockerSendQuestion.otherDay(monday, unmarked: ["Maya S"]).message
            == "This replaces what the office has for that day. Maya S isn't marked; the rest go.")
    }
}
