import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// Back in Class: a child who left early and came back returns to present or
// late, whichever they left from, keeping the morning's arrival and the trip
// out ("out 11:15–12:40"). Their pickup is done, and a stray tap on a child
// who has gone changes nothing.
@Suite("Attendance back in class")
@MainActor
struct AttendanceBackInClassTests {

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

    private struct Fixture {
        let store: CDAttendanceStore
        let record: CDAttendanceRecord
        let student: CDStudent
    }

    /// A record for `day`, marked `first` and then Left Early.
    private func leftEarly(from first: AttendanceStatus, on day: Date? = nil) throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = makeStudent(in: context)
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: student, on: day ?? today))
        if first != .unmarked { store.updateStatus(record, to: first) }
        store.updateStatus(record, to: .leftEarly)
        return Fixture(store: store, record: record, student: student)
    }

    @Test("Back returns a present child to present, keeping the arrival and the trip")
    func backToPresent() throws {
        let fixture = try leftEarly(from: .present)
        let store = fixture.store, record = fixture.record
        record.markedAt = clock(8, 2)
        record.leftAt = clock(11, 15)
        #expect(record.statusBeforeLeavingRaw == AttendanceStatus.present.rawValue)

        #expect(store.markBack(record, at: clock(12, 40)))
        #expect(record.status == .present)
        #expect(record.markedAt == clock(8, 2))
        #expect(record.leftAt == clock(11, 15))
        #expect(record.returnedAt == clock(12, 40))
        #expect(record.statusBeforeLeavingRaw == nil)
    }

    @Test("Back returns a late child to late")
    func backToLate() throws {
        let fixture = try leftEarly(from: .tardy)
        let store = fixture.store, record = fixture.record
        #expect(store.markBack(record, at: clock(12, 40)))
        #expect(record.status == .tardy)
    }

    @Test("Back from a Left Early with no arrival mark is present")
    func backWithoutArrival() throws {
        let fixture = try leftEarly(from: .unmarked)
        let store = fixture.store, record = fixture.record
        #expect(record.statusBeforeLeavingRaw == nil)
        #expect(store.markBack(record, at: clock(12, 40)))
        #expect(record.status == .present)
    }

    @Test("Back only applies to a child marked Left Early")
    func backNeedsLeftEarly() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = makeStudent(in: context)
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: student, on: today))
        store.updateStatus(record, to: .present)
        #expect(!store.markBack(record))
        #expect(record.returnedAt == nil)
    }

    @Test("Back clears the pickup time that took them out")
    func backClearsPickup() throws {
        let fixture = try leftEarly(from: .present)
        let store = fixture.store, record = fixture.record
        store.updateLeavesAt(record, to: clock(11, 0))
        #expect(store.markBack(record, at: clock(12, 40)))
        #expect(record.leavesAt == nil)
    }

    @Test("Back on a day gone by keeps the trip's start but records no return time")
    func backOnAnotherDay() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let fixture = try leftEarly(from: .present, on: yesterday)
        let store = fixture.store, record = fixture.record
        #expect(store.markBack(record))
        #expect(record.status == .present)
        #expect(record.returnedAt == nil)
    }

    @Test("Any other mark ends the trip; leaving again shows the latest departure")
    func otherMarksEndTheTrip() throws {
        let fixture = try leftEarly(from: .present)
        let store = fixture.store, record = fixture.record
        store.markBack(record, at: clock(12, 40))

        #expect(store.updateStatus(record, to: .leftEarly))
        #expect(record.returnedAt == nil)
        #expect(record.statusBeforeLeavingRaw == AttendanceStatus.present.rawValue)

        store.markBack(record, at: clock(13, 0))
        #expect(store.updateStatus(record, to: .tardy))
        #expect(record.leftAt == nil)
        #expect(record.returnedAt == nil)

        store.updateStatus(record, to: .leftEarly)
        #expect(store.updateStatus(record, to: .unmarked))
        #expect(record.statusBeforeLeavingRaw == nil)
    }

    @Test("Reset Day clears a trip and its Undo puts it back")
    func resetDayRestoresTrip() throws {
        let fixture = try leftEarly(from: .tardy)
        let store = fixture.store, record = fixture.record, student = fixture.student
        store.markBack(record, at: clock(12, 40))
        let leftAt = record.leftAt

        let snapshots = try store.resetDay(for: today, students: [student])
        #expect(record.returnedAt == nil)
        #expect(record.leftAt == nil)

        #expect(store.restore(snapshots).count == 1)
        #expect(record.status == .tardy)
        #expect(record.leftAt == leftAt)
        #expect(record.returnedAt == clock(12, 40))
    }

    @Test("The trip reads on present and late marks that came back, and nowhere else")
    func tripText() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = makeStudent(in: context)
        let record = CDAttendanceRecord(context: context)
        record.studentID = student.cloudKitKey
        record.date = today
        record.status = .present
        record.leftAt = clock(11, 15)
        record.returnedAt = clock(12, 40)
        func row() -> AttendanceRow { AttendanceRow(student: student, record: record, shortName: "Maya", day: today) }

        let left = AttendanceClock.string(clock(11, 15))
        let back = AttendanceClock.string(clock(12, 40))
        #expect(AttendanceRules.tripText(row()) == "out \(left)–\(back)")
        #expect(AttendanceStatusMenu.header(for: row(), markedBy: nil)?.contains("out \(left)–\(back)") == true)

        record.returnedAt = nil
        #expect(AttendanceRules.tripText(row()) == "out at \(left)")

        // Still gone: the tile shows when they left, not a trip.
        record.status = .leftEarly
        #expect(AttendanceRules.tripText(row()) == nil)
        #expect(AttendanceRules.allowsBack(for: row()))

        // An older build's mark clears leftAt, so a stale return never shows.
        record.status = .present
        record.leftAt = nil
        record.returnedAt = clock(12, 40)
        #expect(AttendanceRules.tripText(row()) == nil)
        #expect(!AttendanceRules.allowsBack(for: row()))
    }

    @Test("A tap on a child who left early does nothing, in either phase")
    func tapLeavesLeftEarlyAlone() {
        #expect(AttendanceRules.statusAfterTap(from: .leftEarly, in: .arrival) == nil)
        #expect(AttendanceRules.statusAfterTap(from: .leftEarly, in: .late) == nil)
    }

    @Test("Back counts the child in the room again")
    func backCountsHere() throws {
        let fixture = try leftEarly(from: .present)
        let store = fixture.store, record = fixture.record, student = fixture.student
        func row() -> AttendanceRow { AttendanceRow(student: student, record: record, shortName: "Maya", day: today) }
        #expect(!row().isInRoom)
        store.markBack(record, at: clock(12, 40))
        #expect(row().isInRoom)
    }
}
