import Foundation

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
}
