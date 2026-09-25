import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The attendance log view's old computed properties, verbatim, with `Date()` pinned to
/// `now` so both sides see the same instant.
private struct OldAttendanceLog {
    let allRecords: [CDAttendanceRecord]
    let roster: [CDStudent]
    let show: Bool
    let namesRaw: String
    let selectedStudentIDs: Set<UUID>
    let selectedStatuses: Set<AttendanceStatus>
    let selectedDateRange: AttendanceLogView.DateRangeFilter
    let customStartDate: Date
    let customEndDate: Date
    let searchText: String
    let calendar: Calendar
    let now: Date

    var students: [CDStudent] {
        let scoped: [CDStudent]
        if let bounds = dateRangeBounds {
            scoped = roster.filterActive(in: DateRange(start: bounds.start, end: bounds.end))
        } else {
            scoped = roster
        }
        return TestStudentsFilter.filterVisible(scoped, show: show, namesRaw: namesRaw)
    }

    var studentsByID: [UUID: CDStudent] {
        Dictionary(students.compactMap { s in s.id.map { ($0, s) } }, uniquingKeysWith: { first, _ in first })
    }

    var dateRangeBounds: (start: Date, end: Date)? {
        switch selectedDateRange {
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
            return (start, end)
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return (start, end)
        case .lastMonth:
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? now
            return (start, thisMonthStart)
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let endStart = calendar.startOfDay(for: customEndDate)
            let end = calendar.date(byAdding: .day, value: 1, to: endStart) ?? customEndDate
            return (start, end)
        case .allTime:
            return nil
        }
    }

    var filteredRecords: [CDAttendanceRecord] {
        allRecords.filter { record in
            if record.status == .unmarked { return false }
            if let bounds = dateRangeBounds {
                guard let date = record.date else { return false }
                if date < bounds.start || date >= bounds.end { return false }
            }
            if !selectedStudentIDs.isEmpty {
                guard let studentID = record.studentIDUUID else { return false }
                if !selectedStudentIDs.contains(studentID) { return false }
            }
            if !selectedStatuses.isEmpty {
                if !selectedStatuses.contains(record.status) { return false }
            }
            if !searchText.isEmpty {
                guard let studentID = record.studentIDUUID,
                      let student = studentsByID[studentID] else { return false }
                let name = student.shortName.lowercased()
                let query = searchText.lowercased()
                if !name.contains(query) { return false }
            }
            return true
        }
    }

    var summaryStats: AttendanceLogView.AttendanceSummary {
        var present = 0, absent = 0, tardy = 0, leftEarly = 0
        for record in filteredRecords {
            switch record.status {
            case .present: present += 1
            case .absent: absent += 1
            case .tardy: tardy += 1
            case .leftEarly: leftEarly += 1
            case .unmarked: break
            }
        }
        return AttendanceLogView.AttendanceSummary(
            present: present, absent: absent, tardy: tardy,
            leftEarly: leftEarly, total: filteredRecords.count
        )
    }

    var groupedByDay: [(day: Date, items: [CDAttendanceRecord])] {
        let dict = filteredRecords
            .grouped { calendar.startOfDay(for: $0.date ?? Date.distantPast) }
            .mapValues { arr in arr.sorted { lhs, rhs in
                let lhsName = studentsByID[lhs.studentIDUUID ?? UUID()]?.firstName ?? ""
                let rhsName = studentsByID[rhs.studentIDUUID ?? UUID()]?.firstName ?? ""
                return lhsName < rhsName
            }}
        let days = dict.keys.sorted(by: >)
        return days.map { ($0, dict[$0] ?? []) }
    }
}

private struct LogCase: CustomStringConvertible {
    let range: AttendanceLogView.DateRangeFilter
    let search: String
    let studentIDs: Set<UUID>
    let statuses: Set<AttendanceStatus>
    let show: Bool
    var description: String {
        "\(range.rawValue) search=\(search) students=\(studentIDs.count) statuses=\(statuses) show=\(show)"
    }
}

/// The attendance log now filters once per render through `AttendanceLogFilter`
/// instead of re-deriving everything from computed properties on each read.
/// These pin that for every timeframe, with and without a search, a student
/// or a status filter, the records, the summary counts and the day grouping
/// (days and the order within each day) are exactly what the old view code
/// produced.
@Suite("Attendance log filter")
@MainActor
struct AttendanceLogFilterTests {

    private struct Fixture {
        let records: [CDAttendanceRecord]
        let roster: [CDStudent]
        let maya: CDStudent
        let now: Date
    }

    private func seed(in context: NSManagedObjectContext) throws -> Fixture {
        let now = try CoreDataTestHelpers.day("2026-09-17").addingTimeInterval(12 * 3600)
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stein")
        let mark = CoreDataTestHelpers.seedStudent(in: context, firstName: "Mark", lastName: "Levi")
        let avi = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avi", lastName: "Cohen")
        let rina = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rina", lastName: "Peretz", enrollmentStatus: .withdrawn,
            dateWithdrawn: try CoreDataTestHelpers.day("2026-08-25")
        )
        let danny = CoreDataTestHelpers.seedStudent(in: context, firstName: "Danny", lastName: "De Berry")
        let roster = [maya, mark, avi, rina, danny]

        func add(_ day: String, hour: Double, _ student: CDStudent?, _ status: AttendanceStatus) throws {
            let record = CDAttendanceRecord(context: context)
            record.studentIDUUID = student?.id ?? UUID()
            record.date = try CoreDataTestHelpers.day(day).addingTimeInterval(hour * 3600)
            record.status = status
        }
        // Several children on one day, so the within-day name order matters.
        try add("2026-09-17", hour: 9, maya, .present)
        try add("2026-09-17", hour: 9, mark, .absent)
        try add("2026-09-17", hour: 9, danny, .present)
        try add("2026-09-17", hour: 8, avi, .tardy)
        try add("2026-09-16", hour: 9, maya, .leftEarly)
        try add("2026-09-16", hour: 9, mark, .present)
        try add("2026-09-16", hour: 9, nil, .present) // no student on file
        try add("2026-09-15", hour: 9, avi, .unmarked)
        try add("2026-09-15", hour: 9, maya, .absent)
        try add("2026-09-02", hour: 9, mark, .tardy)
        try add("2026-09-01", hour: 0, maya, .present) // the month's first instant
        try add("2026-08-31", hour: 23.9, avi, .present) // the last instant of last month
        try add("2026-08-20", hour: 9, maya, .present)
        try add("2026-08-20", hour: 9, rina, .absent)
        try add("2026-08-20", hour: 9, mark, .absent)
        try add("2026-07-10", hour: 9, avi, .present)
        let undated = CDAttendanceRecord(context: context)
        undated.studentIDUUID = maya.id
        undated.date = nil
        undated.status = .present
        let unparsable = CDAttendanceRecord(context: context)
        unparsable.studentID = "not-a-uuid"
        unparsable.date = now
        unparsable.status = .absent
        #expect(CoreDataTestHelpers.save(context))

        // The fetch's own order: newest first.
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDAttendanceRecord.date, ascending: false)]
        let records = context.safeFetch(request)
        #expect(records.count == 18)
        return Fixture(records: records, roster: roster, maya: maya, now: now)
    }

    /// Every timeframe, with and without a search (either case, a full short
    /// name, a miss), a student filter, a status filter, and test students.
    private func allCases(mayaID: UUID) -> [LogCase] {
        var cases: [LogCase] = []
        for range in AttendanceLogView.DateRangeFilter.allCases {
            for search in ["", "ma", "MA", "avi c", "zzz"] {
                for studentIDs in [Set<UUID>(), [mayaID]] {
                    for statuses in [Set<AttendanceStatus>(), [.absent, .tardy]] {
                        for show in [false, true] {
                            cases.append(LogCase(
                                range: range, search: search, studentIDs: studentIDs, statuses: statuses, show: show
                            ))
                        }
                    }
                }
            }
        }
        return cases
    }

    /// Runs one case both ways and compares; returns whether it listed anything.
    private func compare(_ testCase: LogCase, _ fixture: Fixture, window custom: (Date, Date)) -> Bool {
        let calendar = AppCalendar.shared
        let namesRaw = TestStudentsFilter.defaultNames
        let old = OldAttendanceLog(
            allRecords: fixture.records, roster: fixture.roster, show: testCase.show, namesRaw: namesRaw,
            selectedStudentIDs: testCase.studentIDs, selectedStatuses: testCase.statuses,
            selectedDateRange: testCase.range, customStartDate: custom.0, customEndDate: custom.1,
            searchText: testCase.search, calendar: calendar, now: fixture.now
        )
        let bounds = AttendanceLogFilter.bounds(
            for: testCase.range, customStart: custom.0, customEnd: custom.1, calendar: calendar, now: fixture.now
        )
        let students = AttendanceLogFilter.students(
            from: fixture.roster, bounds: bounds, show: testCase.show, namesRaw: namesRaw
        )
        let byID = AttendanceLogFilter.studentsByID(students)
        let records = AttendanceLogFilter.records(
            fixture.records,
            matching: AttendanceLogFilter.Criteria(
                bounds: bounds, studentIDs: testCase.studentIDs,
                statuses: testCase.statuses, searchText: testCase.search
            ),
            studentsByID: byID
        )
        #expect(students.map(\.objectID) == old.students.map(\.objectID), "\(testCase)")
        #expect(records.map(\.objectID) == old.filteredRecords.map(\.objectID), "\(testCase)")

        let summary = AttendanceLogFilter.summary(of: records)
        let oldSummary = old.summaryStats
        #expect(summary.present == oldSummary.present, "\(testCase)")
        #expect(summary.absent == oldSummary.absent, "\(testCase)")
        #expect(summary.tardy == oldSummary.tardy, "\(testCase)")
        #expect(summary.leftEarly == oldSummary.leftEarly, "\(testCase)")
        #expect(summary.total == oldSummary.total, "\(testCase)")

        let grouped = AttendanceLogFilter.groupedByDay(records, studentsByID: byID, calendar: calendar)
        let oldGrouped = old.groupedByDay
        #expect(grouped.map(\.day) == oldGrouped.map(\.day), "\(testCase)")
        #expect(
            grouped.map { $0.items.map(\.objectID) } == oldGrouped.map { $0.items.map(\.objectID) },
            "\(testCase)"
        )
        return !records.isEmpty
    }

    @Test("Records, summary and day grouping match the old view code for every filter combination")
    func matchesOldComputation() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let fixture = try seed(in: context)
        let custom = try (CoreDataTestHelpers.day("2026-08-15"), CoreDataTestHelpers.day("2026-09-02"))
        let cases = allCases(mayaID: try #require(fixture.maya.id))
        #expect(cases.count == 200)
        let listed = cases.filter { compare($0, fixture, window: custom) }.count
        // The fixture exercises real rows, not just empty results.
        #expect(listed >= 40)
    }

    @Test("Each timeframe's window and fetch predicate")
    func timeframeWindows() throws {
        let calendar = AppCalendar.shared
        let now = try CoreDataTestHelpers.day("2026-09-17").addingTimeInterval(12 * 3600)
        let september = try CoreDataTestHelpers.day("2026-09-01")
        let october = try CoreDataTestHelpers.day("2026-10-01")
        let august = try CoreDataTestHelpers.day("2026-08-01")
        func window(_ range: AttendanceLogView.DateRangeFilter) -> AttendanceLogFilter.Bounds? {
            AttendanceLogFilter.bounds(for: range, customStart: now, customEnd: now, calendar: calendar, now: now)
        }
        let month = try #require(window(.thisMonth))
        #expect(month.start == september)
        #expect(month.end == october)
        let last = try #require(window(.lastMonth))
        #expect(last.start == august)
        #expect(last.end == september)
        #expect(window(.allTime)?.start == nil)
        #expect(AttendanceLogFilter.fetchPredicate(for: nil) == nil)
        let predicate = try #require(AttendanceLogFilter.fetchPredicate(for: month))
        let same = NSPredicate(format: "date >= %@ AND date < %@", september as NSDate, october as NSDate)
        #expect(predicate == same)
    }
}
