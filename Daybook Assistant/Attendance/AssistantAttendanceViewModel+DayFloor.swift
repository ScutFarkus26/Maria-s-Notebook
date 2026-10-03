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
              let next = SchoolDayChecker.schoolDay(from: date, forward: forward, using: context),
              forward || isOnOrAfterEarliestDay(next) else { return }
        load(next)
    }
}
