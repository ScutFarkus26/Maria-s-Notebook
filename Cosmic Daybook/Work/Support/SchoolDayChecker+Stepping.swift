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
}
