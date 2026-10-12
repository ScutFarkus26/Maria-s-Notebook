import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The student detail's attendance badges count the child's school-year rows
/// once per body pass, one record per day, with late arrivals counted by
/// `cameLate` (bug hunt 2026-10-11, #34). The numbers must be the
/// fetch-dedupe-and-filter's, saved or not.
@Suite("Attendance info row counts")
@MainActor
struct AttendanceInfoRowCountTests {

    /// The reference read: every row of the year, one per day, then filtered.
    private func referenceCount(
        _ status: AttendanceStatus, studentID: UUID?, on date: Date, in context: NSManagedObjectContext
    ) throws -> Int {
        let calendar = AppCalendar.shared
        let start = FloridaGradeCalculator.schoolYearStart(for: date, calendar: calendar)
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else { return 0 }
        let studentIDString = studentID?.uuidString ?? ""
        let descriptor = CDFetchRequest(CDAttendanceRecord.self)
        descriptor.predicate = NSPredicate(
            format: "studentID == %@ AND date >= %@ AND date < %@",
            studentIDString, start as CVarArg, end as CVarArg
        )
        let records = try context.fetch(descriptor).deduplicatedPerStudentDay()
        return records.filter { status == .tardy ? $0.cameLate : $0.status == status }.count
    }

    private func record(
        _ statusRaw: String, for studentID: UUID, on date: Date, in context: NSManagedObjectContext
    ) -> CDAttendanceRecord {
        let record = CoreDataTestHelpers.seedAttendance(in: context, studentID: studentID, date: date)
        record.statusRaw = statusRaw
        return record
    }

    /// A school year of marks for Ora — tardies, absences, presents, a
    /// duplicate day, the year's first instant and the next year's, an unknown
    /// raw value — plus last year's and a classmate's, saved; then unsaved
    /// edits of every kind on top.
    private func seedAndEdit(
        _ context: NSManagedObjectContext, ora: UUID, reference: Date
    ) throws {
        let calendar = AppCalendar.shared
        let start = FloridaGradeCalculator.schoolYearStart(for: reference, calendar: calendar)
        let end = try #require(calendar.date(byAdding: .year, value: 1, to: start))
        func day(_ offset: Int) throws -> Date {
            try #require(calendar.date(byAdding: .day, value: offset, to: start))
        }
        let classmate = UUID()
        var saved: [CDAttendanceRecord] = []
        for offset in [3, 10, 10, 40] { saved.append(record("tardy", for: ora, on: try day(offset), in: context)) }
        for offset in [5, 60] { saved.append(record("absent", for: ora, on: try day(offset), in: context)) }
        for offset in [1, 2, 4, 6] { saved.append(record("present", for: ora, on: try day(offset), in: context)) }
        saved.append(record("absent", for: ora, on: start, in: context))
        saved.append(record("tardy", for: ora, on: end, in: context))
        saved.append(record("Tardy", for: ora, on: try day(7), in: context))
        saved.append(record("tardy", for: ora, on: try day(-2), in: context))
        saved.append(record("tardy", for: classmate, on: try day(8), in: context))
        saved.append(record("absent", for: classmate, on: try day(9), in: context))
        #expect(CoreDataTestHelpers.save(context))

        // Unsaved: a new tardy, an absence turned tardy, a tardy deleted.
        _ = record("tardy", for: ora, on: try day(90), in: context)
        saved[4].statusRaw = "tardy"
        context.delete(saved[0])
    }

    private func expectSameCounts(in context: NSManagedObjectContext) throws {
        let ora = UUID()
        let reference = try CoreDataTestHelpers.day("2026-10-15")
        try seedAndEdit(context, ora: ora, reference: reference)

        let counted = try AttendanceInfoRow.schoolYearCounts(studentID: ora, on: reference, in: context)
        #expect(counted.tardy == (try referenceCount(.tardy, studentID: ora, on: reference, in: context)))
        #expect(counted.absent == (try referenceCount(.absent, studentID: ora, on: reference, in: context)))
        // Not vacuous: 4 saved tardies, one deleted, one absence turned tardy,
        // one new — the duplicate day counted once.
        #expect(counted == AttendanceInfoRow.SchoolYearCounts(tardy: 4, absent: 2))
        #expect(try AttendanceInfoRow.schoolYearCounts(studentID: nil, on: reference, in: context) == .init())
    }

    @Test("Counts equal the fetch-dedupe-and-filter on the in-memory store")
    func countsMatchInMemory() throws {
        try expectSameCounts(in: try CoreDataTestHelpers.makeContext())
    }

    @Test("Counts equal the fetch-dedupe-and-filter on SQLite, with unsaved edits pending")
    func countsMatchOnSQLite() throws {
        try expectSameCounts(in: try CoreDataTestHelpers.makeSplitStoreContext())
    }
}
