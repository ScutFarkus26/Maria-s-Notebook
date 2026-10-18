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

    /// What one render of the log shows.
    struct Listing {
        /// The Students menu (`students(from:bounds:show:namesRaw:)`).
        let students: [CDStudent]
        /// Who each row is named by, searched by and sorted by.
        let studentsByID: [UUID: CDStudent]
        /// The rows, in fetch order.
        let records: [CDAttendanceRecord]
    }

    /// The Students menu, the names and the rows for `criteria`, from the
    /// fetched records and the whole roster (`RosterStore.all`).
    ///
    /// Rows are named, searched and sorted by the whole roster, not the
    /// window's: a start date typed in after a child's first marks left
    /// those rows "Unknown Student", and unsearchable. A hidden test
    /// student's rows aren't listed or counted, as the menu doesn't offer
    /// her (bug hunt 2026-10-17, #3).
    static func listing(
        _ all: some Sequence<CDAttendanceRecord>,
        roster: [CDStudent],
        criteria: Criteria,
        show: Bool,
        namesRaw: String
    ) -> Listing {
        let students = students(from: roster, bounds: criteria.bounds, show: show, namesRaw: namesRaw)
        let byID = studentsByID(roster)
        let visible = Set(TestStudentsFilter.filterVisible(roster, show: show, namesRaw: namesRaw).compactMap(\.id))
        let hidden = Set(roster.compactMap(\.id)).subtracting(visible)
        return Listing(
            students: students, studentsByID: byID,
            records: records(all, matching: criteria, studentsByID: byID, hiding: hidden)
        )
    }

    /// The records the log lists, in fetch order: one per child per day,
    /// marked, inside the window, not a hidden student's (`hidden`), for the
    /// chosen students and statuses, and whose student's short name contains
    /// the search text (case-insensitively).
    ///
    /// A day two devices marked before syncing holds a copy from each; the
    /// log showed and counted both, where every other screen shows the one
    /// `deduplicatedPerStudentDay` picks. That pick comes first, so a filter
    /// never finds the copy the grid doesn't show (bug hunt 2026-10-17, #2).
    /// A record with no date has no day to share and stays. The pick runs
    /// over the window's rows only, not the whole table on every redraw: a
    /// day's copies share its date, so they fall inside the window together.
    static func records(
        _ all: some Sequence<CDAttendanceRecord>,
        matching criteria: Criteria,
        studentsByID: [UUID: CDStudent],
        hiding hidden: Set<UUID> = []
    ) -> [CDAttendanceRecord] {
        let query = criteria.searchText.isEmpty ? nil : criteria.searchText.lowercased()
        let inside = all.filter { isInside($0, criteria.bounds) }
        let shown = Set(inside.deduplicatedPerStudentDay().map(ObjectIdentifier.init))
        return inside.filter { record in
            // Unmarked records are never listed.
            (record.date == nil || shown.contains(ObjectIdentifier(record)))
                && record.status != .unmarked
                && !isHidden(record, hidden)
                && matchesSelection(record, criteria)
                && matchesSearch(record, query: query, studentsByID: studentsByID)
        }
    }

    private static func isHidden(_ record: CDAttendanceRecord, _ hidden: Set<UUID>) -> Bool {
        guard !hidden.isEmpty, let studentID = record.studentIDUUID else { return false }
        return hidden.contains(studentID)
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
