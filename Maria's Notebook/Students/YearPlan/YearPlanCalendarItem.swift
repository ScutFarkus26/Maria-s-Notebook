import Foundation

/// Unified display item for the Year Plan calendar.
/// Wraps either a `CDYearPlanEntry` (aspirational plan) or a `CDLessonAssignment`
/// (actual scheduled/given presentation not linked to any plan entry).
struct YearPlanCalendarItem: Identifiable {
    let id: UUID
    let lessonID: String
    let date: Date
    let kind: Kind

    /// Resolved when the item is built, not when it is drawn: whether an entry
    /// is `given` depends on `YearPlanSatisfaction`, which reads the store, and
    /// this is looked at once per calendar cell per render pass.
    let displayStatus: DisplayStatus

    enum Kind {
        case planEntry(CDYearPlanEntry)
        case assignment(CDLessonAssignment)
    }

    init(
        id: UUID,
        lessonID: String,
        date: Date,
        kind: Kind,
        satisfaction: YearPlanSatisfaction = .none
    ) {
        self.id = id
        self.lessonID = lessonID
        self.date = date
        self.kind = kind
        self.displayStatus = Self.resolveStatus(kind, satisfaction: satisfaction)
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
        /// The lesson has been given, so the intention is answered.
        case given
        case scheduled
        case presented
    }

    private static func resolveStatus(
        _ kind: Kind, satisfaction: YearPlanSatisfaction
    ) -> DisplayStatus {
        switch kind {
        case .planEntry(let entry):
            // Given beats the stored status: whether the entry was pencilled in
            // or promoted onto the calendar, the lesson happening is the end of
            // the story. Skipped is the guide's own decision and outranks it.
            if entry.status == .skipped { return .skipped }
            if entry.isSatisfied(by: satisfaction) { return .given }
            switch entry.status {
            case .promoted: return .promoted
            case .skipped: return .skipped
            case .planned: return entry.isBehindPace(satisfiedBy: satisfaction) ? .behindPace : .planned
            }
        case .assignment(let assignment):
            return assignment.isPresented ? .presented : .scheduled
        }
    }

    /// Whether this item can be rescheduled/removed from the Year Plan.
    /// A lesson already given has nothing left to re-target.
    var isEditable: Bool {
        switch displayStatus {
        case .planned, .behindPace: return true
        default: return false
        }
    }
}
