import Foundation
import CoreData

/// One child's attendance over a range, as a school asks for it: the school
/// days she was in the class, and of those the days she came (present, late
/// or left early), was absent, came late, and left early.
nonisolated struct AttendanceTally: Equatable, Sendable {
    var daysEnrolled = 0
    var present = 0
    var absent = 0
    var late = 0
    var leftEarly = 0
}

/// The one rule the attendance totals count by: the absence and tardy
/// reports and the Mac's insights (domain-logic review 2026-11-20, R19).
///
/// A day counts for a child when it is a school day and she was in the
/// class: her dates put her on the roll (`AttendanceRoster.wasEnrolled`), or
/// she was marked that day and hadn't left before it. A mark on a day later
/// made a day off no longer counts (it stays on the record), nor does one
/// after her last day. A mark before her start date still counts: start
/// dates aren't reliable history (`AttendanceRoster`), and the record is
/// proof she was there.
nonisolated enum AttendanceTallies {

    /// Whether `student` had left the class before `day`: departed, with a
    /// last day (inclusive) before it.
    static func hadLeft(_ student: CDStudent, before day: Date, calendar: Calendar = AppCalendar.shared) -> Bool {
        guard student.enrollmentStatus != .enrolled, let lastDay = student.dateWithdrawn else { return false }
        return calendar.startOfDay(for: lastDay) < calendar.startOfDay(for: day)
    }

    /// The records that count, out of records already deduplicated
    /// (`deduplicatedPerStudentDay`): on a school day, for one of
    /// `students`, before she left. A marked-but-unknown child is left out.
    static func countedRecords(
        _ records: [CDAttendanceRecord],
        students: [CDStudent],
        daysOff: Set<Date>,
        calendar: Calendar = AppCalendar.shared
    ) -> [CDAttendanceRecord] {
        let byKey = Dictionary(students.map { ($0.cloudKitKey, $0) }, uniquingKeysWith: { first, _ in first })
        return records.filter { record in
            guard let date = record.date, let student = byKey[record.studentID] else { return false }
            let day = calendar.startOfDay(for: date)
            return !daysOff.contains(day) && !hadLeft(student, before: day, calendar: calendar)
        }
    }

    /// Each of `students`' tallies over `days` (each day's start, the
    /// range's every day), by student id, from records already
    /// deduplicated. Days enrolled are the school days among `days` that
    /// her dates put her in the class, plus any day a counted mark says so.
    static func tallies(
        records: [CDAttendanceRecord],
        students: [CDStudent],
        days: [Date],
        daysOff: Set<Date>,
        calendar: Calendar = AppCalendar.shared
    ) -> [String: AttendanceTally] {
        let counted = countedRecords(records, students: students, daysOff: daysOff, calendar: calendar)
        var markedDays: [String: Set<Date>] = [:]
        var result: [String: AttendanceTally] = [:]
        for record in counted {
            guard let date = record.date else { continue }
            var tally = result[record.studentID] ?? AttendanceTally()
            switch record.status {
            case .present: tally.present += 1
            case .tardy: tally.present += 1
            case .leftEarly:
                tally.present += 1
                tally.leftEarly += 1
            case .absent: tally.absent += 1
            case .unmarked: break
            }
            if record.cameLate { tally.late += 1 }
            result[record.studentID] = tally
            markedDays[record.studentID, default: []].insert(calendar.startOfDay(for: date))
        }
        let schoolDays = days.map { calendar.startOfDay(for: $0) }.filter { !daysOff.contains($0) }
        for student in students {
            let key = student.cloudKitKey
            let marked = markedDays[key] ?? []
            let enrolled = schoolDays.count { day in
                marked.contains(day) || AttendanceRoster.wasEnrolled(student, on: day, calendar: calendar)
            }
            guard enrolled > 0 || result[key] != nil else { continue }
            result[key, default: AttendanceTally()].daysEnrolled = enrolled
        }
        return result
    }

    /// Every day from `range`'s first to its last, each day's start.
    static func days(in range: ClosedRange<Date>, calendar: Calendar = AppCalendar.shared) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: range.lowerBound)
        let last = calendar.startOfDay(for: range.upperBound)
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = calendar.startOfDay(for: next)
        }
        return days
    }

    /// The days with no school from `range`'s first day to its last, by
    /// `SchoolDayChecker`'s rule.
    static func daysOff(
        in range: ClosedRange<Date>, context: NSManagedObjectContext, calendar: Calendar = AppCalendar.shared
    ) -> Set<Date> {
        let start = calendar.startOfDay(for: range.lowerBound)
        let last = calendar.startOfDay(for: range.upperBound)
        guard let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
        return SchoolDayChecker.nonSchoolDaySet(in: start..<end, using: context, calendar: calendar)
    }
}
