import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// A day's roll: enrolled that day by their dates, or holding a record that day.
// The record rule is what keeps history intact when start dates are really the
// day the child was typed in.
@Suite("Attendance roster by day")
@MainActor
struct AttendanceRosterTests {

    private let day: Date
    private let dayBefore: Date
    private let dayAfter: Date

    init() throws {
        day = try CoreDataTestHelpers.day("2026-09-16")
        dayBefore = try CoreDataTestHelpers.day("2026-09-15")
        dayAfter = try CoreDataTestHelpers.day("2026-09-17")
    }

    private func student(
        _ first: String,
        in context: NSManagedObjectContext,
        status: CDStudent.EnrollmentStatus = .enrolled,
        started: Date? = nil,
        lastDay: Date? = nil
    ) -> CDStudent {
        let student = CoreDataTestHelpers.seedStudent(
            in: context, firstName: first, enrollmentStatus: status, dateStarted: started, dateWithdrawn: lastDay
        )
        student.id = UUID()
        return student
    }

    private func names(_ students: [CDStudent]) -> Set<String> {
        Set(students.map(\.firstName))
    }

    @Test("Start dates: none or on/before the day counts; a later start doesn't")
    func startDates() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let undated = student("Undated", in: context)
        let sameDay = student("SameDay", in: context, started: day.addingTimeInterval(9 * 3600))
        let earlier = student("Earlier", in: context, started: dayBefore)
        let later = student("Later", in: context, started: dayAfter)

        let roll = AttendanceRoster.students(
            on: day, from: [undated, sameDay, earlier, later], recordStudentIDs: []
        )
        #expect(names(roll) == ["Undated", "SameDay", "Earlier"])
    }

    @Test("Departed children count through their last day, inclusive; with no date, never")
    func departures() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let leftToday = student("LeftToday", in: context, status: .withdrawn, lastDay: day)
        let leftYesterday = student("LeftYesterday", in: context, status: .transferred, lastDay: dayBefore)
        let leftLater = student("LeftLater", in: context, status: .withdrawn, lastDay: dayAfter)
        let noDate = student("NoDate", in: context, status: .withdrawn)

        let roll = AttendanceRoster.students(
            on: day, from: [leftToday, leftYesterday, leftLater, noDate], recordStudentIDs: []
        )
        #expect(names(roll) == ["LeftToday", "LeftLater"])
    }

    @Test("A record that day puts a child on the roll whatever the dates say")
    func recordWins() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let typedInLater = student("TypedInLater", in: context, started: dayAfter)
        let departedNoDate = student("DepartedNoDate", in: context, status: .withdrawn)
        let ids: Set<String> = [typedInLater.id!.uuidString, departedNoDate.id!.uuidString]

        let roll = AttendanceRoster.students(
            on: day, from: [typedInLater, departedNoDate], recordStudentIDs: ids
        )
        #expect(names(roll) == ["TypedInLater", "DepartedNoDate"])
    }

    @Test("The fetch predicate picks the same children as the in-memory rule")
    func predicateAgrees() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let everyone = [
            student("Undated", in: context),
            student("Later", in: context, started: dayAfter),
            student("SameDay", in: context, started: day.addingTimeInterval(9 * 3600)),
            student("LeftToday", in: context, status: .withdrawn, lastDay: day),
            student("LeftYesterday", in: context, status: .transferred, lastDay: dayBefore),
            student("NoDate", in: context, status: .withdrawn),
            student("RecordOnly", in: context, status: .withdrawn)
        ]
        _ = context.safeSave()
        let recordOnly = try #require(everyone.last?.id?.uuidString)

        for ids in [Set<String>(), [recordOnly]] {
            let request = CDFetchRequest(CDStudent.self)
            request.predicate = AttendanceRoster.predicate(on: day, recordStudentIDs: ids)
            let fetched = context.safeFetch(request)
            let inMemory = AttendanceRoster.students(on: day, from: everyone, recordStudentIDs: ids)
            #expect(names(fetched) == names(inMemory))
        }
    }

    @Test("The day's record ids include blank records")
    func recordIDs() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let marked = student("Marked", in: context)
        let blank = student("Blank", in: context)
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: marked, on: day))
        store.updateStatus(record, to: .present)
        _ = try store.ensureRecord(for: blank, on: day)
        _ = try store.ensureRecord(for: blank, on: dayAfter)

        let ids = AttendanceRoster.recordStudentIDs(on: day, in: context)
        #expect(ids == [marked.id!.uuidString, blank.id!.uuidString])
    }
}
