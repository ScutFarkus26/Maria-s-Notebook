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

    // MARK: - Strong dedup pre-check

    // The launch and post-import passes call deduplicateAttendanceRecordsStrong on a
    // table that almost never has duplicates. A dictionary pre-check on the two
    // grouping columns answers that without faulting a single record into the context.

    @Test("With no duplicates, the strong pass answers from the columns alone")
    func strongDedupSkipsFullFetchWhenClean() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let day = AppCalendar.startOfDay(Date())
        let previousDay = AppCalendar.addingDays(-1, to: day)
        let studentA = UUID().uuidString
        let studentB = UUID().uuidString

        _ = makeRecord(in: context, studentID: studentA, date: day, status: .present)
        _ = makeRecord(in: context, studentID: studentB, date: day, status: .absent)
        _ = makeRecord(in: context, studentID: studentA, date: previousDay, status: .tardy)
        #expect(CoreDataTestHelpers.save(context))

        // Drop the freshly inserted objects so registration is a true signal of
        // what the dedup pass itself faulted in.
        context.reset()

        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: context) == 0)
        // A dictionary-result fetch registers nothing; the old full-table object
        // fetch would have registered all three rows.
        #expect(context.registeredObjects.isEmpty)
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).count == 3)
    }

    @Test("The pre-check still lets a real duplicate through to the full pass")
    func strongDedupCollapsesAfterPreCheck() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let day = AppCalendar.startOfDay(Date())
        let studentID = UUID().uuidString

        _ = makeRecord(in: context, studentID: studentID, date: day, status: .unmarked)
        // Same calendar day, later time of day — the grouping key normalizes it.
        _ = makeRecord(in: context, studentID: studentID,
                       date: day.addingTimeInterval(3600), status: .absent)
        #expect(CoreDataTestHelpers.save(context))
        context.reset()

        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: context) == 1)
        let survivors = context.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
        #expect(survivors.count == 1)
        #expect(survivors.first?.status == .absent)
    }
}
