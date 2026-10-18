import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, #2 and #3: the attendance log listed every CloudKit
/// copy of a child's day (both counted, and Delete took off only one), named
/// children only if their start date fell in the window ("Unknown Student"
/// for a child whose start date was typed in late), and counted hidden test
/// students.
@Suite("Attendance log (Fix1017 At)")
@MainActor
struct AttendanceLogFix1017AtTests {

    private let context: NSManagedObjectContext
    private let calendar = AppCalendar.shared

    init() throws {
        context = try CoreDataTestHelpers.makeContext()
    }

    @discardableResult
    private func record(
        _ student: CDStudent, _ day: String, _ status: AttendanceStatus, modified: TimeInterval = 0
    ) throws -> CDAttendanceRecord {
        let record = CDAttendanceRecord(context: context)
        record.studentIDUUID = student.id
        record.date = try CoreDataTestHelpers.day(day)
        record.status = status
        record.modifiedAt = Date(timeIntervalSince1970: 1_790_000_000 + modified)
        return record
    }

    private func window(_ from: String, _ through: String) throws -> AttendanceLogFilter.Bounds? {
        AttendanceLogFilter.bounds(
            for: .custom, customStart: try CoreDataTestHelpers.day(from),
            customEnd: try CoreDataTestHelpers.day(through), calendar: calendar, now: Date()
        )
    }

    private func listing(
        roster: [CDStudent], bounds: AttendanceLogFilter.Bounds?,
        statuses: Set<AttendanceStatus> = [], search: String = "", show: Bool = false
    ) -> AttendanceLogFilter.Listing {
        AttendanceLogFilter.listing(
            context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)),
            roster: roster,
            criteria: AttendanceLogFilter.Criteria(bounds: bounds, statuses: statuses, searchText: search),
            show: show,
            namesRaw: TestStudentsFilter.defaultNames
        )
    }

    // #2
    @Test("Two devices' copies of a child's day show as one row, the one the grid shows")
    func duplicatesShowOnce() throws {
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        try record(maya, "2026-09-17", .present, modified: 0)
        try record(maya, "2026-09-17", .absent, modified: 60)
        try record(maya, "2026-09-16", .tardy)
        #expect(context.safeSave())
        let september = try window("2026-09-01", "2026-09-30")

        let shown = listing(roster: [maya], bounds: september)
        #expect(shown.records.count == 2)
        let summary = AttendanceLogFilter.summary(of: shown.records)
        #expect(summary.total == 2)
        #expect(summary.present == 0)
        #expect(summary.absent == 1)
        // The losing copy doesn't come back through a status filter.
        #expect(listing(roster: [maya], bounds: september, statuses: [.present]).records.isEmpty)
    }

    // #3
    @Test("Rows are named from the whole roster, and hidden test students aren't counted")
    func namesFromWholeRosterWithoutTestStudents() throws {
        let lea = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Lea", lastName: "Moss", dateStarted: try CoreDataTestHelpers.day("2025-12-09")
        )
        let danny = CoreDataTestHelpers.seedStudent(in: context, firstName: "Danny", lastName: "De Berry")
        try record(lea, "2025-10-01", .present)
        try record(danny, "2025-10-01", .present)
        #expect(context.safeSave())
        let october = try window("2025-10-01", "2025-10-31")
        let leaID = try #require(lea.id)

        let shown = listing(roster: [lea, danny], bounds: october)
        #expect(shown.studentsByID[leaID] === lea)
        #expect(shown.records.map(\.studentIDUUID) == [leaID])
        #expect(AttendanceLogFilter.summary(of: shown.records).total == 1)
        #expect(listing(roster: [lea, danny], bounds: october, search: "lea").records.count == 1)
        // The Students menu still offers only children active in the window.
        #expect(!shown.students.contains(lea))

        // Shown when the teacher asks to see them.
        #expect(listing(roster: [lea, danny], bounds: october, show: true).records.count == 2)
    }

    // #2: Delete
    @Test("Delete takes off every copy of the child's day, so none comes back on the grid")
    func deleteClearsEveryCopy() throws {
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let ari = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ari", lastName: "Cedar")
        let shown = try record(maya, "2026-09-17", .absent, modified: 60)
        try record(maya, "2026-09-17", .present, modified: 0)
        try record(maya, "2026-09-16", .present)
        try record(ari, "2026-09-17", .present)
        #expect(context.safeSave())

        let store = CDAttendanceStore(context: context, role: .leadGuide)
        #expect(store.delete(shown))
        #expect(context.safeSave())
        let left = context.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
        let mayaID = try #require(maya.id)
        let day = try CoreDataTestHelpers.day("2026-09-17")
        #expect(!left.contains { $0.studentIDUUID == mayaID && $0.date == day })
        #expect(left.count == 2)
    }
}
