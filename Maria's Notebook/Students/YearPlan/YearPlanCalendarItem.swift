import Foundation

/// Unified display item for the Year Plan calendar.
/// Wraps either a `CDYearPlanEntry` (aspirational plan) or a `CDLessonAssignment`
/// (actual scheduled/given presentation not linked to any plan entry).
struct YearPlanCalendarItem: Identifiable {
    let id: UUID
    let lessonID: String
    let date: Date
    let kind: Kind

    enum Kind {
        case planEntry(CDYearPlanEntry)
        case assignment(CDLessonAssignment)
    }

    // MARK: - Accessors

    var planEntry: CDYearPlanEntry? {
        if case .planEntry(let entry) = kind { return entry }
        return nil
    }

    var assignment: CDLessonAssignment? {
        if case .assignment(let a) = kind { return a }
        return nil
    }

    // MARK: - Display Status

    enum DisplayStatus {
        case planned
        case behindPace
        case promoted
        case skipped
        case scheduled
        case presented
    }

    var displayStatus: DisplayStatus {
        switch kind {
        case .planEntry(let entry):
            switch entry.status {
            case .promoted: return .promoted
            case .skipped: return .skipped
            case .planned: return entry.isBehindPace ? .behindPace : .planned
            }
        case .assignment(let assignment):
            return assignment.isPresented ? .presented : .scheduled
        }
    }

    /// Whether this item can be rescheduled/removed from the Year Plan.
    var isEditable: Bool {
        if case .planEntry(let entry) = kind { return entry.isPlanned }
        return false
    }
}
