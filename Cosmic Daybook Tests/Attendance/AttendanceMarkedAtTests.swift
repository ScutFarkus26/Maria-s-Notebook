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

    @Test("Left Early keeps the arrival and dates the departure; leaving it clears the departure")
    func leftEarlyKeepsArrival() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent("Tzofia", in: context)
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)

        let record = try #require(try store.ensureRecord(for: student, on: day))
        #expect(store.updateStatus(record, to: .tardy))
        let arrived = try #require(record.markedAt)
        #expect(record.leftAt == nil)

        #expect(store.updateStatus(record, to: .leftEarly))
        #expect(record.markedAt == arrived)
        #expect(record.leftAt != nil)

        #expect(store.updateStatus(record, to: .present))
        #expect(record.leftAt == nil)
        #expect(record.markedAt != nil)

        #expect(store.updateStatus(record, to: .unmarked))
        #expect(record.markedAt == nil && record.leftAt == nil)
    }

    @Test("Left Early from absent or unmarked has no arrival, only the departure")
    func leftEarlyWithoutArrival() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent("Naomi", in: context)
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)

        let record = try #require(try store.ensureRecord(for: student, on: day))
        #expect(store.updateStatus(record, to: .absent))
        #expect(store.updateStatus(record, to: .leftEarly))
        #expect(record.markedAt == nil)
        #expect(record.leftAt != nil)
    }

    @Test("A mark made on another day than its own gets no time")
    func otherDaysGetNoTime() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent("Dalia", in: context)
        let today = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)

        for offset in [-2, 3] {
            let day = AppCalendar.addingDays(offset, to: today)
            let record = try #require(try store.ensureRecord(for: student, on: day))
            #expect(store.updateStatus(record, to: .present))
            #expect(record.markedAt == nil)
            #expect(store.updateStatus(record, to: .leftEarly))
            #expect(record.markedAt == nil && record.leftAt == nil)
        }

        let yesterday = AppCalendar.addingDays(-1, to: today)
        let closed = try store.markUnmarkedAbsent(for: yesterday, students: [student])
        #expect(closed.count == 1)
        #expect(closed.allSatisfy { $0.status == .absent && $0.markedAt == nil })
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

    @Test("Closing arrival and marking all present fetch the day once but keep ensureRecord's answers")
    func batchKeepsOneRecordPerChild() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let maya = makeStudent("Maya", in: context)
        let sarah = makeStudent("Sarah", in: context)
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)

        // Sarah's record is a pending insert; Maya is named twice.
        let pending = try #require(try store.ensureRecord(for: sarah, on: day))
        let closed = try store.markUnmarkedAbsent(for: day, students: [maya, sarah, maya])
        #expect(closed.count == 2)
        #expect(closed.contains { $0 === pending })
        #expect(try store.loadRecords(for: day).count == 2)

        let present = try store.markAllPresent(for: day, students: [maya, sarah, maya])
        #expect(present.count == 3)
        #expect(Set(present.map(\.objectID)).count == 2)
        #expect(present.allSatisfy { $0.status == .present })
        #expect(try store.loadRecords(for: day).count == 2)
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
