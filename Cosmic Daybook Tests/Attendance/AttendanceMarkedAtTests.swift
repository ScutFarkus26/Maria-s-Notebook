import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// `markedAt` dates the current status ("arrived 8:12"), and closing the
// arrival window marks only the children nobody has marked yet.
@Suite("Attendance mark times & closing arrival")
@MainActor
struct AttendanceMarkedAtTests {

    private func makeStudent(_ first: String, in context: NSManagedObjectContext) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = "Example"
        return student
    }

    @Test("A status change dates the mark; a note edit doesn't; unmarked clears it")
    func statusChangesDateTheMark() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent("Etty", in: context)
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)

        let record = try #require(try store.ensureRecord(for: student, on: day))
        #expect(record.markedAt == nil)

        #expect(store.updateStatus(record, to: .present))
        let marked = try #require(record.markedAt)

        #expect(store.updateNote(record, to: "dentist, back by 11"))
        #expect(record.markedAt == marked)

        #expect(!store.updateStatus(record, to: .present))
        #expect(record.markedAt == marked)

        #expect(store.updateStatus(record, to: .unmarked))
        #expect(record.markedAt == nil)
    }

    @Test("Closing arrival marks only the unmarked absent, creating records as needed")
    func markUnmarkedAbsent() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let here = makeStudent("Maya", in: context)
        let blank = makeStudent("Sarah", in: context)
        let noRecord = makeStudent("Etty", in: context)
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)

        let hereRecord = try #require(try store.ensureRecord(for: here, on: day))
        store.updateStatus(hereRecord, to: .present)
        let hereMarked = hereRecord.markedAt
        _ = try store.ensureRecord(for: blank, on: day)

        let changed = try store.markUnmarkedAbsent(for: day, students: [here, blank, noRecord])

        #expect(Set(changed.map(\.studentID)) == Set([blank, noRecord].compactMap { $0.id?.uuidString }))
        #expect(changed.allSatisfy { $0.status == .absent && $0.markedAt != nil })
        #expect(hereRecord.status == .present)
        #expect(hereRecord.markedAt == hereMarked)
        #expect(try store.loadRecords(for: day).count == 3)
    }

    @Test("Closing arrival does nothing on a locked day")
    func lockedDayIsLeftAlone() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent("Etty", in: context)
        let day = AppCalendar.startOfDay(Date())
        #expect(AttendanceDayLocks.setLocked(true, for: day, role: .leadGuide, in: context))
        let store = CDAttendanceStore(context: context)

        #expect(try store.markUnmarkedAbsent(for: day, students: [student]).isEmpty)
        #expect(try store.loadRecords(for: day).isEmpty)
    }
}
