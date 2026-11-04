import Foundation
import CoreData

nonisolated extension SchoolDayChecker {
    /// The next (`forward`) or previous school day from `date`, skipping
    /// weekends and the guide's days off; nil if none within a year. The
    /// Daybook Assistant's ‹ › arrows step with it.
    static func schoolDay(
        from date: Date,
        forward: Bool,
        using context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) -> Date? {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<366 {
            guard let moved = calendar.date(byAdding: .day, value: forward ? 1 : -1, to: day) else { return nil }
            day = moved
            if !isNonSchoolDay(day, using: context) { return day }
        }
        return nil
    }

    /// The same walk over days off already read: `daysOff` holds the
    /// start of each day with no school (by `calendar`) for the year beside
    /// `date`. The Daybook Assistant reads them from the classroom share
    /// only (`AssistantAttendanceViewModel.schoolDay`).
    static func schoolDay(
        from date: Date,
        forward: Bool,
        daysOff: Set<Date>,
        calendar: Calendar = .current
    ) -> Date? {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<366 {
            guard let moved = calendar.date(byAdding: .day, value: forward ? 1 : -1, to: day) else { return nil }
            day = moved
            if !daysOff.contains(day) { return day }
        }
        return nil
    }
}
