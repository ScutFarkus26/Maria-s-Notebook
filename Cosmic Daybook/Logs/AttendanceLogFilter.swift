// AttendanceLogFilter.swift
// What the attendance log shows for a set of filters.
//
// The view used to read its filtered records through computed properties:
// the summary strip read five counts that each walked the records twice, the
// day grouping and the empty check walked them again (about twelve passes per
// render), the per-record filter recomputed the timeframe's calendar bounds,
// a search rebuilt the roster dictionary for every record, and the day sort
// rebuilt it twice per comparison. These are the same rules as plain
// functions of their inputs, so a render computes the bounds, the roster and
// the filtered records once and derives the summary and the grouping from
// that one array.

import CoreData
import Foundation

enum AttendanceLogFilter {

    typealias Bounds = (start: Date, end: Date)

    /// The window a timeframe covers, `[start, end)`, or nil for all time.
    static func bounds(
        for range: AttendanceLogView.DateRangeFilter,
        customStart: Date,
        customEnd: Date,
        calendar: Calendar,
        now: Date
    ) -> Bounds? {
        switch range {
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
            let start = calendar.startOfDay(for: customStart)
            let endStart = calendar.startOfDay(for: customEnd)
            let end = calendar.date(byAdding: .day, value: 1, to: endStart) ?? customEnd
            return (start, end)
        case .allTime:
            return nil
        }
    }

    /// The fetch predicate for a window: only the visible records (backed by
    /// the AttendanceRecord `byDate` index), or every record for all time.
    static func fetchPredicate(for bounds: Bounds?) -> NSPredicate? {
        guard let bounds else { return nil }
        return NSPredicate(format: "date >= %@ AND date < %@", bounds.start as NSDate, bounds.end as NSDate)
    }

    /// The students the log offers and names: active in the window (not
    /// enrolled-only, so former students' history stays visible), with test
    /// students hidden unless the teacher shows them.
    static func students(from base: [CDStudent], bounds: Bounds?, show: Bool, namesRaw: String) -> [CDStudent] {
        let scoped: [CDStudent]
        if let bounds {
            scoped = base.filterActive(in: DateRange(start: bounds.start, end: bounds.end))
        } else {
            scoped = base
        }
        return TestStudentsFilter.filterVisible(scoped, show: show, namesRaw: namesRaw)
    }

    /// Students by id; the first of any CloudKit duplicate wins.
    static func studentsByID(_ students: [CDStudent]) -> [UUID: CDStudent] {
        Dictionary(students.compactMap { s in s.id.map { ($0, s) } }, uniquingKeysWith: { first, _ in first })
    }

    /// The filters the log's controls set.
    struct Criteria {
        var bounds: Bounds?
        var studentIDs: Set<UUID> = []
        var statuses: Set<AttendanceStatus> = []
        var searchText = ""
    }

    /// The records the log lists, in fetch order: marked, inside the window,
    /// for the chosen students and statuses, and whose student's short name
    /// contains the search text (case-insensitively).
    static func records(
        _ all: some Sequence<CDAttendanceRecord>,
        matching criteria: Criteria,
        studentsByID: [UUID: CDStudent]
    ) -> [CDAttendanceRecord] {
        let query = criteria.searchText.isEmpty ? nil : criteria.searchText.lowercased()
        return all.filter { record in
            // Unmarked records are never listed.
            record.status != .unmarked
                && isInside(record, criteria.bounds)
                && matchesSelection(record, criteria)
                && matchesSearch(record, query: query, studentsByID: studentsByID)
        }
    }

    private static func isInside(_ record: CDAttendanceRecord, _ bounds: Bounds?) -> Bool {
        guard let bounds else { return true }
        guard let date = record.date else { return false }
        return date >= bounds.start && date < bounds.end
    }

    private static func matchesSelection(_ record: CDAttendanceRecord, _ criteria: Criteria) -> Bool {
        if !criteria.studentIDs.isEmpty {
            guard let studentID = record.studentIDUUID, criteria.studentIDs.contains(studentID) else { return false }
        }
        return criteria.statuses.isEmpty || criteria.statuses.contains(record.status)
    }

    /// `query` is the lowercased search text, nil when the field is empty.
    private static func matchesSearch(
        _ record: CDAttendanceRecord, query: String?, studentsByID: [UUID: CDStudent]
    ) -> Bool {
        guard let query else { return true }
        guard let studentID = record.studentIDUUID, let student = studentsByID[studentID] else { return false }
        return student.shortName.lowercased().contains(query)
    }

    /// The counts strip above the log.
    static func summary(of records: [CDAttendanceRecord]) -> AttendanceLogView.AttendanceSummary {
        var present = 0, absent = 0, tardy = 0, leftEarly = 0
        for record in records {
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
            leftEarly: leftEarly, total: records.count
        )
    }

    /// The records by day, newest day first, each day's rows by first name.
    static func groupedByDay(
        _ records: [CDAttendanceRecord],
        studentsByID: [UUID: CDStudent],
        calendar: Calendar
    ) -> [(day: Date, items: [CDAttendanceRecord])] {
        func firstName(_ record: CDAttendanceRecord) -> String {
            record.studentIDUUID.flatMap { studentsByID[$0] }?.firstName ?? ""
        }
        let dict = records
            .grouped { calendar.startOfDay(for: $0.date ?? Date.distantPast) }
            .mapValues { day in day.sorted { firstName($0) < firstName($1) } }
        let days = dict.keys.sorted(by: >)
        return days.map { ($0, dict[$0] ?? []) }
    }
}
