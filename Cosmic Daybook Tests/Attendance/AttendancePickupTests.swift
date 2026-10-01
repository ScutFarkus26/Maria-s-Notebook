import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// Leaving Early…: a pickup time on the shared record ("leaves 1:30") is a
// plan, not a mark. It leaves the status alone, survives a status change,
// goes with Reset Day (and comes back with its Undo), and keeps a record from
// counting as blank.
@Suite("Attendance pickup times")
@MainActor
struct AttendancePickupTests {

    private let today = Calendar.current.startOfDay(for: Date())

    private func clock(_ hour: Int, _ minute: Int, on day: Date? = nil) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day ?? today) ?? today
    }

    private func makeStudent(in context: NSManagedObjectContext) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = "Maya"
        student.lastName = "Stone"
        return student
    }

    private func row(_ status: AttendanceStatus, leavesAt: Date?) throws -> AttendanceRow {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = makeStudent(in: context)
        let record = CDAttendanceRecord(context: context)
        record.studentID = student.cloudKitKey
        record.date = today
        record.status = status
        record.leavesAt = leavesAt
        return AttendanceRow(student: student, record: record, shortName: "Maya", day: today)
    }

    @Test("Setting a pickup marks nothing, and a mark keeps the pickup")
    func pickupIsNotAMark() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = makeStudent(in: context)
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: student, on: today))

        #expect(store.updateLeavesAt(record, to: clock(13, 30)))
        #expect(record.status == .unmarked)
        #expect(record.markedAt == nil)
        #expect(!AttendanceRecordSnapshot.isBlank(record))
        #expect(!store.updateLeavesAt(record, to: clock(13, 30)))

        #expect(store.updateStatus(record, to: .present))
        #expect(record.leavesAt == clock(13, 30))
        #expect(store.updateStatus(record, to: .leftEarly))
        #expect(record.leavesAt == clock(13, 30))

        #expect(store.updateLeavesAt(record, to: nil))
        #expect(record.leavesAt == nil)
    }

    @Test("Reset Day clears a pickup and its Undo puts it back")
    func resetDayClearsAndRestores() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = makeStudent(in: context)
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: student, on: today))
        store.updateLeavesAt(record, to: clock(11, 0))

        let snapshots = try store.resetDay(for: today, students: [student])
        #expect(snapshots.count == 1)
        #expect(record.leavesAt == nil)

        #expect(store.restore(snapshots).count == 1)
        #expect(record.leavesAt == clock(11, 0))
    }

    @Test("The tile says when they leave until they're marked gone or absent")
    func pickupText() throws {
        let time = clock(13, 30)
        let expected = "leaves \(AttendanceClock.string(time))"
        #expect(AttendanceRules.pickupText(try row(.unmarked, leavesAt: time)) == expected)
        #expect(AttendanceRules.pickupText(try row(.present, leavesAt: time)) == expected)
        #expect(AttendanceRules.pickupText(try row(.tardy, leavesAt: time)) == expected)
        #expect(AttendanceRules.pickupText(try row(.leftEarly, leavesAt: time)) == nil)
        #expect(AttendanceRules.pickupText(try row(.absent, leavesAt: time)) == nil)
        #expect(AttendanceRules.pickupText(try row(.present, leavesAt: nil)) == nil)
    }

    @Test("Leaving Early… is offered today and ahead, not on days gone by or once gone")
    func whenOffered() throws {
        let calendar = Calendar.current
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let friday = try #require(calendar.date(byAdding: .day, value: 3, to: today))
        let here = try row(.present, leavesAt: nil)
        #expect(AttendanceRules.allowsPickup(for: here, on: today))
        #expect(AttendanceRules.allowsPickup(for: try row(.unmarked, leavesAt: nil), on: friday))
        #expect(!AttendanceRules.allowsPickup(for: here, on: yesterday))
        #expect(!AttendanceRules.allowsPickup(for: try row(.leftEarly, leavesAt: nil), on: today))
        #expect(!AttendanceRules.allowsPickup(for: try row(.absent, leavesAt: nil), on: today))
    }

    @Test("The picker's time lands on the record's day; it starts on the next half hour, or noon ahead")
    func pickerTimes() throws {
        let calendar = Calendar.current
        let friday = try #require(calendar.date(byAdding: .day, value: 3, to: today))
        // Picked today at 1:30, saved for Friday: Friday at 1:30.
        #expect(AttendanceRules.pickup(clock(13, 30), on: friday) == clock(13, 30, on: friday))

        let unset = try row(.unmarked, leavesAt: nil)
        #expect(AttendanceRules.suggestedPickup(for: unset, on: today, now: clock(10, 5)) == clock(10, 30))
        #expect(AttendanceRules.suggestedPickup(for: unset, on: today, now: clock(10, 30)) == clock(11, 0))
        #expect(AttendanceRules.suggestedPickup(for: unset, on: friday, now: clock(10, 5)) == clock(12, 0, on: friday))
        let set = try row(.unmarked, leavesAt: clock(14, 15))
        #expect(AttendanceRules.suggestedPickup(for: set, on: today, now: clock(10, 5)) == clock(14, 15))
    }

    @Test("Removing duplicates keeps a pickup set on the losing copy")
    func dedupKeepsPickup() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = makeStudent(in: context)
        let marked = CDAttendanceRecord(context: context)
        marked.studentID = student.cloudKitKey
        marked.date = today
        marked.status = .present
        let planned = CDAttendanceRecord(context: context)
        planned.studentID = student.cloudKitKey
        planned.date = today
        planned.leavesAt = clock(13, 30)
        #expect(context.safeSave())

        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: context) == 1)

        let left = context.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
        #expect(left.count == 1)
        #expect(left.first?.status == .present)
        #expect(left.first?.leavesAt == clock(13, 30))
    }
}
