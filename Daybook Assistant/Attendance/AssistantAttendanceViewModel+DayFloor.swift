import Foundation
import CoreData

// The guide shares this school year only (`ClassroomShareScope` in the notebook), so the
// grid pages no earlier than the share's first day with attendance, and a child the guide
// has just taken out of the share is never marked.

extension AssistantAttendanceViewModel {

    /// False on the share's first day with attendance: there is nothing of this school year
    /// before it (`AssistantDayRoll.earliestRecordDay`).
    var canStepBack: Bool {
        guard let earliestDay else { return true }
        return date > earliestDay
    }

    func isOnOrAfterEarliestDay(_ day: Date) -> Bool {
        guard let earliestDay else { return true }
        return day >= earliestDay
    }

    /// A row whose child has just gone from the store (the guide took her out of the share)
    /// is never marked: the day reloads instead. True when it did.
    func reloadIfGone(_ row: Row) -> Bool {
        guard row.studentIsGone else { return false }
        load()
        return true
    }

    /// Moves to the next (`forward`) or previous school day, skipping weekends
    /// and the guide's days off. Stays put if none is found within a year.
    /// Never back past the share's first day with attendance (`canStepBack`).
    func step(forward: Bool) {
        guard forward || canStepBack,
              let next = Self.schoolDay(from: date, forward: forward, in: context),
              forward || isOnOrAfterEarliestDay(next) else { return }
        load(next)
    }

    /// The next (`forward`) or previous school day by the guide's calendar
    /// only (`AttendanceEmailLog.nonSchoolDays`), as `dayOff` and the day
    /// number read it; nil if none within a year. With a notebook of her own
    /// on the same Apple Account, the arrows skipped a class day that
    /// notebook had off and stopped on its school Saturdays, which showed as
    /// a weekend (bug hunt 2026-11-03, #5). One read of the year's days off,
    /// not two fetches for each day stepped over.
    static func schoolDay(from date: Date, forward: Bool, in context: NSManagedObjectContext) -> Date? {
        let calendar = AppCalendar.shared
        let day = calendar.startOfDay(for: date)
        // The year the walk may cover, beside `day`.
        guard let far = calendar.date(byAdding: .day, value: forward ? 367 : -366, to: day) else { return nil }
        let daysOff = AttendanceEmailLog.nonSchoolDays(
            in: forward ? day..<far : far..<day, using: context, calendar: calendar
        )
        return SchoolDayChecker.schoolDay(from: day, forward: forward, daysOff: daysOff, calendar: calendar)
    }
}
