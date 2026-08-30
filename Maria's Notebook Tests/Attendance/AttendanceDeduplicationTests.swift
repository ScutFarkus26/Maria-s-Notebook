import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

// Regression coverage for CloudKit attendance duplicates: two devices opening the
// same day each create their own CDAttendanceRecord, and reports must count them
// as one (matching the grid, which shows one status per student per day).
@Suite("Attendance CloudKit dedup")
@MainActor
struct AttendanceDeduplicationTests {

    private func makeRecord(
        in context: NSManagedObjectContext,
        studentID: String,
        date: Date,
        status: AttendanceStatus,
        id: UUID = UUID()
    ) -> CDAttendanceRecord {
        let record = CDAttendanceRecord(context: context)
        record.id = id
        record.studentID = studentID
        record.date = date
        record.status = status
        return record
    }

    @Test("Duplicate records for the same student and day collapse to one")
    func duplicatesCollapse() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let day = AppCalendar.startOfDay(Date())
        let studentID = UUID().uuidString

        _ = makeRecord(in: context, studentID: studentID, date: day, status: .tardy)
        _ = makeRecord(in: context, studentID: studentID, date: day, status: .tardy)

        let range = day...day
        let records = AttendanceInsightsService.fetchRecords(
            in: range, context: context, fetchLabel: "test"
        )
        #expect(records.count == 1)

        let counts = AttendanceInsightsService.dayCounts(in: range, context: context)
        #expect(counts[day]?.tardy == 1)
    }

    @Test("A marked record beats an unmarked duplicate")
    func markedBeatsUnmarked() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let day = AppCalendar.startOfDay(Date())
        let studentID = UUID().uuidString

        _ = makeRecord(in: context, studentID: studentID, date: day, status: .unmarked)
        _ = makeRecord(in: context, studentID: studentID, date: day, status: .absent)

        let records = AttendanceInsightsService.fetchRecords(
            in: day...day, context: context, fetchLabel: "test"
        )
        #expect(records.count == 1)
        #expect(records.first?.status == .absent)
    }

    @Test("The winner among equally-marked duplicates is the lowest id, on every device")
    func deterministicWinner() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let day = AppCalendar.startOfDay(Date())
        let studentID = UUID().uuidString

        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
        _ = makeRecord(in: context, studentID: studentID, date: day, status: .tardy, id: highID)
        _ = makeRecord(in: context, studentID: studentID, date: day, status: .absent, id: lowID)

        let records = AttendanceInsightsService.fetchRecords(
            in: day...day, context: context, fetchLabel: "test"
        )
        #expect(records.first?.id == lowID)
    }

    @Test("Among equally-marked duplicates, the latest modification wins")
    func latestModificationWins() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let day = AppCalendar.startOfDay(Date())
        let studentID = UUID().uuidString

        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
        let older = makeRecord(in: context, studentID: studentID, date: day, status: .tardy, id: lowID)
        older.modifiedAt = day
        let newer = makeRecord(in: context, studentID: studentID, date: day, status: .absent, id: highID)
        newer.modifiedAt = day.addingTimeInterval(600)

        let records = AttendanceInsightsService.fetchRecords(
            in: day...day, context: context, fetchLabel: "test"
        )
        // Last writer wins, even against a lower id — two people marking the
        // same student converge on the most recent mark.
        #expect(records.first?.id == highID)
        #expect(records.first?.status == .absent)
    }

    @Test("Distinct students and distinct days are not collapsed")
    func distinctRecordsKept() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let day = AppCalendar.startOfDay(Date())
        let previousDay = AppCalendar.addingDays(-1, to: day)
        let studentA = UUID().uuidString
        let studentB = UUID().uuidString

        _ = makeRecord(in: context, studentID: studentA, date: day, status: .tardy)
        _ = makeRecord(in: context, studentID: studentB, date: day, status: .tardy)
        _ = makeRecord(in: context, studentID: studentA, date: previousDay, status: .absent)

        let records = AttendanceInsightsService.fetchRecords(
            in: previousDay...day, context: context, fetchLabel: "test"
        )
        #expect(records.count == 3)
    }
}
