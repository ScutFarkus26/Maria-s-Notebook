import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// A child's copies of one day (CloudKit duplicates: two devices marking
// before they synced) when a mark is cleared or Close Arrival is undone
// (bug hunt 2026-10-04, Phase 1 steps 1 and 5).
@Suite("Attendance store: a child's copies of a day")
@MainActor
struct AttendanceStoreCopiesTests {

    private let context: NSManagedObjectContext
    private let day = AppCalendar.startOfDay(Date())
    private let student: CDStudent

    init() throws {
        context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ari")
    }

    /// Another device's record for the child, as if synced in.
    @discardableResult
    private func copy(
        _ status: AttendanceStatus, automatic: Bool = false, secondsAgo: TimeInterval
    ) throws -> CDAttendanceRecord {
        let record = CDAttendanceRecord(context: context)
        record.studentID = try #require(student.id?.uuidString)
        record.date = day
        record.status = status
        if automatic { record.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw }
        record.modifiedAt = Date().addingTimeInterval(-secondsAgo)
        return record
    }

    private func shown(_ store: CDAttendanceStore) throws -> CDAttendanceRecord? {
        try store.loadRecords(for: day).deduplicatedPerStudentDay().first
    }

    @Test("Clearing a mark clears the day's other copies too, notes and pickup times kept")
    func unmarkClearsCopies() throws {
        let store = CDAttendanceStore(context: context, role: .assistant)
        let older = try copy(.present, secondsAgo: 120)
        older.note = "Dentist at 2"
        let pickup = day.addingTimeInterval(13 * 3_600)
        older.leavesAt = pickup
        let newer = try copy(.tardy, secondsAgo: 60)
        #expect(try shown(store) === newer)

        #expect(store.unmark(newer))
        #expect(older.status == .unmarked && newer.status == .unmarked)
        #expect(older.note == "Dentist at 2")
        #expect(older.leavesAt == pickup)
        #expect(try shown(store)?.status == .unmarked)
        #expect(!store.unmark(newer), "nothing left to clear")
    }

    @Test("Close Arrival's Undo clears other automatic copies, and leaves a real mark alone")
    func undoAutomaticAbsence() throws {
        let store = CDAttendanceStore(context: context, role: .assistant)
        let closedHere = try #require(try store.markUnmarkedAbsent(for: day, students: [student]).first)
        let closedThere = try copy(.absent, automatic: true, secondsAgo: 60)
        #expect(store.undoAutomaticAbsence(closedHere))
        #expect(closedHere.status == .unmarked && closedThere.status == .unmarked)
        #expect(try !store.arrivalClosed(on: day))

        // Present on another phone that hadn't synced: newer news than the
        // Close Arrival being undone.
        let closedAgain = try #require(try store.markUnmarkedAbsent(for: day, students: [student]).first)
        let present = try copy(.present, secondsAgo: 30)
        #expect(store.undoAutomaticAbsence(closedAgain))
        #expect(present.status == .present)
        #expect(try shown(store) === present)
    }

    @Test("Undo leaves an absence given a reason since, and nothing on a locked day")
    func undoOnlyAnAutomaticAbsence() throws {
        let store = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try store.markUnmarkedAbsent(for: day, students: [student]).first)
        #expect(store.updateAbsenceReason(record, to: .sick))
        #expect(!store.undoAutomaticAbsence(record))
        #expect(record.status == .absent && record.absenceReason == .sick)

        let other = CoreDataTestHelpers.seedStudent(in: context, firstName: "Bea")
        let automatic = try #require(try store.markUnmarkedAbsent(for: day, students: [other]).first)
        #expect(AttendanceDayLocks.setLocked(true, for: day, role: .leadGuide, in: context))
        #expect(!store.undoAutomaticAbsence(automatic))
        #expect(!store.unmark(automatic))
        #expect(AttendanceDeduplication.isAutomaticAbsence(automatic))
    }

    // The plan's check for step 1: after the Undo, a status-only Absent (Siri's
    // "Maya is absent") is a person's absence, not arrival closed.
    @Test("After Close Arrival's Undo, a plain Absent doesn't read as arrival closed")
    func undoThenPlainAbsent() throws {
        let store = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try store.markUnmarkedAbsent(for: day, students: [student]).first)
        #expect(store.undoAutomaticAbsence(record))
        #expect(store.updateStatus(record, to: .absent))
        #expect(!AttendanceDeduplication.isAutomaticAbsence(record))
        #expect(try !store.arrivalClosed(on: day))
    }
}
