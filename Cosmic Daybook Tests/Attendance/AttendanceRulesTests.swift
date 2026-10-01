import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// The rules the notebook's roll now shares with the Daybook Assistant: what a
// tap and a click do, what a day ahead allows, and how a mark reads.
@Suite("Attendance rules")
@MainActor
struct AttendanceRulesTests {

    private let today = Calendar.current.startOfDay(for: Date())
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today }

    private func row(
        _ status: AttendanceStatus,
        reason: AbsenceReason = .none,
        markedAt: Date? = nil,
        leftAt: Date? = nil,
        recordedBy: String? = nil,
        recordedByName: String? = nil
    ) throws -> AttendanceRow {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = "Maya"
        student.lastName = "Stone"
        let record = CDAttendanceRecord(context: context)
        record.studentID = student.cloudKitKey
        record.date = today
        record.status = status
        record.absenceReason = reason
        record.markedAt = markedAt
        record.leftAt = leftAt
        record.recordedBy = recordedBy
        record.recordedByName = recordedByName
        return AttendanceRow(student: student, record: record, shortName: "Maya", day: today)
    }

    private func clock(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
    }

    @Test("A click cycles through every status today")
    func cycleToday() {
        #expect(AttendanceRules.cycle(from: .unmarked, on: today) == .present)
        #expect(AttendanceRules.cycle(from: .present, on: today) == .absent)
        #expect(AttendanceRules.cycle(from: .leftEarly, on: today) == .unmarked)
    }

    @Test("Ahead of the day a click goes between unmarked and absent")
    func cycleAhead() {
        #expect(AttendanceRules.cycle(from: .unmarked, on: tomorrow) == .absent)
        #expect(AttendanceRules.cycle(from: .absent, on: tomorrow) == .unmarked)
        #expect(AttendanceRules.menuStatuses(on: tomorrow) == [.absent, .unmarked])
        #expect(AttendanceRules.menuStatuses(on: today).count == 5)
    }

    @Test("A tile's tap: present during arrival, late after it closes")
    func tapRule() {
        #expect(AttendanceRules.statusAfterTap(from: .unmarked, in: .arrival) == .present)
        #expect(AttendanceRules.statusAfterTap(from: .present, in: .arrival) == .unmarked)
        #expect(AttendanceRules.statusAfterTap(from: .absent, in: .late) == .tardy)
        #expect(AttendanceRules.statusAfterTap(from: .present, in: .late) == nil)
    }

    @Test("A mark reads with its time, and Left Early with both")
    func markSummary() throws {
        let arrived = clock(8, 2)
        let left = clock(13, 15)
        let present = try row(.present, markedAt: arrived)
        #expect(AttendanceRules.markSummary(present) == "Present at \(AttendanceClock.string(arrived))")
        let leftEarly = try row(.leftEarly, markedAt: arrived, leftAt: left)
        let times = "\(AttendanceClock.string(arrived)) → \(AttendanceClock.string(left))"
        #expect(AttendanceRules.markSummary(leftEarly) == "Left Early \(times)")
        #expect(AttendanceRules.leftEarlyTimes(leftEarly) == times)
        #expect(AttendanceRules.markSummary(try row(.absent, reason: .sick)) == "Absent, Sick")
        #expect(AttendanceRules.markSummary(try row(.unmarked)) == nil)
    }

    @Test("The menu header names the assistant, and leaves the guide's own marks unlabelled")
    func header() throws {
        let byRivka = try row(.present, recordedBy: "assistant", recordedByName: "Rivka")
        let name = AttendanceRules.markerName(for: byRivka, myRecordName: "guide", myName: nil, guideName: "you")
        #expect(name == "Rivka")
        #expect(AttendanceStatusMenu.header(for: byRivka, markedBy: name) == "Present · by Rivka")

        let mine = try row(.present, recordedBy: "leadGuide")
        #expect(AttendanceRules.markerName(for: mine, myRecordName: "guide", myName: nil, guideName: "you") == "you")
    }

    @Test("The tally leaves out what's zero")
    func tally() throws {
        let rows = [try row(.present), try row(.present), try row(.absent), try row(.unmarked)]
        #expect(AttendanceRules.tally(rows) == "2 here · 1 absent · 1 not marked")
    }

    @Test("Late and left early count as here, with the brackets saying how many")
    func tallyCountsLateAsHere() throws {
        let rows = [try row(.present), try row(.tardy), try row(.tardy), try row(.leftEarly), try row(.unmarked)]
        #expect(AttendanceRules.tally(rows) == "4 here (2 late, 1 left early) · 1 not marked")
        #expect(AttendanceRules.tally([try row(.tardy), try row(.absent)]) == "1 here (1 late) · 1 absent")
        #expect(AttendanceRules.shortTally(rows) == "4 here · 1 not marked")
    }
}
