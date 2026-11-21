// ScheduleChildrenAway.swift
// Which children are away from class on each day, from attendance, for the
// day's busy picture (`AwayTimes`) and the Schedules warnings: a child marked
// Absent is away all day; one due to be picked up early (`leavesAt`) or
// already gone (Left Early, not back) is away from that time on. Read only:
// attendance is written through `CDAttendanceStore`. Notebook only.

import CoreData
import Foundation

enum ScheduleChildrenAway {

    /// The entity whose saves change what this reads.
    nonisolated static let entityName = "AttendanceRecord"

    /// The children away from class on each day from `start` through `end`,
    /// keyed by start of day: one fetch for the range, each child's day read
    /// from the copy that counts (`deduplicatedPerStudentDay`).
    static func days(
        from start: Date,
        through end: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> [Date: [ScheduleChildAway]] {
        let first = calendar.startOfDay(for: start)
        let after = TimetableService.dayAfter(end, calendar: calendar)
        guard first < after else { return [:] }
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", first as NSDate, after as NSDate)
        var result: [Date: [ScheduleChildAway]] = [:]
        for record in context.safeFetch(request).deduplicatedPerStudentDay() {
            guard let date = record.date, let away = childAway(record, calendar: calendar) else { continue }
            result[calendar.startOfDay(for: date), default: []].append(away)
        }
        for day in result.keys {
            result[day]?.sort { $0.studentID < $1.studentID }
        }
        return result
    }

    /// The children away from class on `day`.
    static func on(
        _ day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> [ScheduleChildAway] {
        days(from: day, through: day, in: context, calendar: calendar)[calendar.startOfDay(for: day)] ?? []
    }

    /// One record's time away: all day for Absent; from the earlier of her
    /// pickup and when she left, for a child leaving early who isn't back.
    /// Nil when she's in class all day. Times on another day don't count.
    nonisolated static func childAway(_ record: CDAttendanceRecord, calendar: Calendar) -> ScheduleChildAway? {
        let studentID = record.studentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !studentID.isEmpty, let day = record.date else { return nil }
        if record.statusRaw == absentRaw { return ScheduleChildAway(studentID: studentID, fromMinute: nil) }
        guard record.returnedAt == nil else { return nil }
        let left = record.statusRaw == leftEarlyRaw ? record.leftAt : nil
        let times = [record.leavesAt, left].compactMap { $0 }.filter { calendar.isDate($0, inSameDayAs: day) }
        guard let leaves = times.min() else { return nil }
        return ScheduleChildAway(studentID: studentID, fromMinute: TimetableDay.minute(of: leaves, calendar: calendar))
    }

    /// `AttendanceStatus` raw values, read as strings so this stays off the main actor.
    nonisolated private static let absentRaw = "absent"
    nonisolated private static let leftEarlyRaw = "leftEarly"
}
