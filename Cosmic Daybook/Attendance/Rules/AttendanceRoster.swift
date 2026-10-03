import Foundation
import CoreData

/// Who belongs on one day's attendance.
///
/// A child is on a day's roll when either
/// - **they have an attendance record that day** — the record is proof they
///   were on the roll, so looking back never hides a mark, whatever their
///   dates say; or
/// - **their dates say so**: started on or before the day (or no start date),
///   and still enrolled, or departed with `dateWithdrawn` — the last day in
///   class, inclusive (`RolloverService`) — on or after it. A departed child
///   with no date shows only where they have a record.
///
/// The record rule matters because start dates aren't reliable history: in
/// Danny's notebook most were typed in as the day the child was entered
/// (29 Nov and 9 Dec 2025) for children who were there from August.
///
/// Used by the notebook's attendance grid, the MCP attendance tools and the
/// Daybook Assistant, which compiles this file by path.
nonisolated enum AttendanceRoster {

    /// `students` narrowed to `day`'s roll. Keeps the input order.
    static func students(
        on day: Date,
        from students: [CDStudent],
        recordStudentIDs: Set<String>,
        calendar: Calendar = .current
    ) -> [CDStudent] {
        students.filter { student in
            if let key = student.id?.uuidString, recordStudentIDs.contains(key) { return true }
            return wasEnrolled(student, on: day, calendar: calendar)
        }
    }

    /// Whether `student`'s dates put them on `day`'s roll.
    static func wasEnrolled(_ student: CDStudent, on day: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        if let started = student.dateStarted, started >= nextDay { return false }
        switch student.enrollmentStatus {
        case .enrolled:
            return true
        case .withdrawn, .transferred:
            guard let lastDay = student.dateWithdrawn else { return false }
            return lastDay >= start
        }
    }

    /// The same roll as a fetch predicate, for a fetch that only wants the
    /// day's children. `recordStudentIDs` are the day's records' student ids.
    static func predicate(
        on day: Date,
        recordStudentIDs: Set<String>,
        calendar: Calendar = .current
    ) -> NSPredicate {
        let start = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let byDates = NSPredicate(
            format: "(dateStarted == nil OR dateStarted < %@) AND "
                + "(enrollmentStatusRaw == %@ OR (enrollmentStatusRaw != %@ AND dateWithdrawn >= %@))",
            nextDay as NSDate,
            CDStudent.EnrollmentStatus.enrolled.rawValue,
            CDStudent.EnrollmentStatus.enrolled.rawValue,
            start as NSDate
        )
        let ids = recordStudentIDs.compactMap(UUID.init(uuidString:))
        guard !ids.isEmpty else { return byDates }
        let withRecords = NSPredicate(format: "id IN %@", ids)
        return NSCompoundPredicate(orPredicateWithSubpredicates: [byDates, withRecords])
    }

    /// Student ids of every attendance record on `day`, blank ones included:
    /// a record means someone put the child on that day's roll.
    static func recordStudentIDs(on day: Date, in context: NSManagedObjectContext) -> Set<String> {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date == %@", day.normalizedDay() as NSDate)
        return Set(context.safeFetch(request).map(\.studentID))
    }
}
