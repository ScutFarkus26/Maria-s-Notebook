// LessonsAndWorkTriage.swift
// The single rule that decides which Lessons & Work list a record belongs in.
//
// The workspace exists to answer three questions about any record:
//
//   Attention    what needs me
//   To Schedule  what I still must plan
//   Scheduled    what is on a day — the calendar pinned beneath both halves
//
// These are states, not places. The workspace is split by *kind* first
// (`WorkspaceKind`), and each half offers its states as a pill row —
// `WorkFilterChip` for work, `PresentationsFilterChip` for presentations.
// Scheduled is a bucket like the others but never a list you switch to: it is
// the surface the rest are dragged onto, so it stays on screen.
//
// Every open presentation and every open work item lands in exactly one of
// them — the buckets do not overlap and they leave no gaps. Finished records
// fall out to `.done`, which is history and lives under Logs.
//
// The rule is pure: it takes value inputs and an explicit reference date, so
// every boundary is testable without Core Data and without a live clock. The
// adapters that build those inputs from managed objects live in
// `LessonsAndWorkTriage+CoreData.swift`.
//
// This type is the one place the question "does this need the guide?" is
// answered. Before it existed, the scope list, the card badge and the printed
// work sheet each computed it separately and disagreed. Anything that needs
// the answer — a list, a badge, a count, a report — asks here.

import Foundation

// MARK: - Bucket

/// Where a presentation or work item sits in the Lessons & Work workspace.
enum TriageBucket: String, CaseIterable, Identifiable, Sendable {
    /// Waiting on the guide: observe the child, or check the work.
    case attention
    /// Has a day on it and that day has not arrived.
    case scheduled
    /// Real and open, but carries no date at all.
    case toSchedule
    /// Finished. Not shown in the workspace; reachable through Logs.
    case done

    var id: Self { self }

    /// The buckets the workspace shows at all. Still three: the partition
    /// splits records into all of them, and a record's bucket is what deep
    /// links resolve against.
    static let workspaceCases: [TriageBucket] = [.attention, .scheduled, .toSchedule]

    /// The buckets a saved list selection may name. `.scheduled` is absent on
    /// purpose — the calendar is pinned beneath whichever half is showing,
    /// because a schedule is where things are dragged *to*, not a list you
    /// switch away to.
    static let listCases: [TriageBucket] = [.attention, .toSchedule]

    var title: String {
        switch self {
        case .attention: "Attention"
        case .scheduled: "Scheduled"
        case .toSchedule: "To Schedule"
        case .done: "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .attention: "exclamationmark.circle"
        case .scheduled: "calendar"
        case .toSchedule: "tray.and.arrow.down"
        case .done: "checkmark.circle"
        }
    }

    var searchPrompt: String {
        switch self {
        case .attention: "Search children, lessons, or work"
        case .scheduled: "Search scheduled lessons or children"
        case .toSchedule: "Search what still needs a day"
        case .done: "Search finished records"
        }
    }

    /// Resolves a saved list selection. Falls back to Attention for an unknown
    /// value, for `.done`, and for `.scheduled` — a value a build that still
    /// had a Scheduled tab could have left behind.
    static func resolved(rawValue: String?) -> Self {
        guard let rawValue, let bucket = Self(rawValue: rawValue),
              listCases.contains(bucket) else {
            return .attention
        }
        return bucket
    }

    /// Where to continue after the guide closes the post-presentation
    /// reflection. An unresolved responsibility comes first; then any work the
    /// reflection just created, which starts life without a date.
    static func afterPresentation(hasOpenFollowUp: Bool, hasOpenWork: Bool) -> Self {
        if hasOpenFollowUp { return .attention }
        if hasOpenWork { return .toSchedule }
        return .attention
    }
}

// MARK: - Inputs

/// Everything the rule needs to place one work item, as plain values.
struct WorkTriageInput: Sendable, Equatable {
    var status: WorkStatus
    var dueAt: Date?
    /// Set when the guide has deliberately put the work aside until a date.
    var restingUntil: Date?
    /// Dates of this work's check-ins that are still in the `.scheduled` state.
    var scheduledCheckInDates: [Date]
    /// School days since the last meaningful touch, per `WorkAgingPolicy`.
    var schoolDaysSinceLastTouch: Int

    init(
        status: WorkStatus,
        dueAt: Date? = nil,
        restingUntil: Date? = nil,
        scheduledCheckInDates: [Date] = [],
        schoolDaysSinceLastTouch: Int = 0
    ) {
        self.status = status
        self.dueAt = dueAt
        self.restingUntil = restingUntil
        self.scheduledCheckInDates = scheduledCheckInDates
        self.schoolDaysSinceLastTouch = schoolDaysSinceLastTouch
    }
}

/// Everything the rule needs to place one presentation, as plain values.
struct PresentationTriageInput: Sendable, Equatable {
    var state: LessonAssignmentState
    var scheduledFor: Date?
    /// True when the presentation was given, carries a follow-up action, and
    /// that action has not been resolved.
    var hasUnresolvedFollowUp: Bool

    init(
        state: LessonAssignmentState,
        scheduledFor: Date? = nil,
        hasUnresolvedFollowUp: Bool = false
    ) {
        self.state = state
        self.scheduledFor = scheduledFor
        self.hasUnresolvedFollowUp = hasUnresolvedFollowUp
    }
}

// MARK: - The rule

enum LessonsAndWorkTriage {

    /// School days of silence before untouched work starts asking for the guide.
    ///
    /// The same threshold that colours the card, so a card cannot look stale
    /// without also being asked for. `AgingPolicy.staleDays` is the one place
    /// the number lives — deliberately not a second literal here.
    static var staleSchoolDays: Int { AgingPolicy.staleDays }

    // MARK: Work

    /// Places one work item.
    ///
    /// Order matters. Completion wins over everything; resting wins over every
    /// reason to nag, because resting *is* a plan; then the four ways work can
    /// ask for the guide; then the two ways it can be planned. Anything left
    /// is open with no date on it, which is precisely "to schedule".
    static func bucket(for work: WorkTriageInput, asOf now: Date = Date()) -> TriageBucket {
        let today = AppCalendar.startOfDay(now)

        if work.status == .complete { return .done }

        // Work the guide deliberately set aside comes back on its own date. It
        // is planned, not neglected — the same reason `WorkAgingPolicy`
        // suppresses overdue and stale while `restingUntil` is in the future.
        if let restingUntil = work.restingUntil, AppCalendar.startOfDay(restingUntil) > today {
            return .scheduled
        }

        if work.status == .review { return .attention }

        if let dueAt = work.dueAt, AppCalendar.startOfDay(dueAt) <= today { return .attention }

        let hasDueCheckIn = work.scheduledCheckInDates.contains { date in
            AppCalendar.startOfDay(date) <= today
        }
        if hasDueCheckIn { return .attention }

        if work.schoolDaysSinceLastTouch >= staleSchoolDays { return .attention }

        // Past dates were all caught above, so any date still here is future.
        if work.dueAt != nil { return .scheduled }
        if !work.scheduledCheckInDates.isEmpty { return .scheduled }

        return .toSchedule
    }

    // MARK: Presentations

    /// Places one presentation.
    ///
    /// Time-independent: a presentation is either given (and then either
    /// carrying an open follow-up or finished) or not yet given, in which case
    /// only the presence of a day matters.
    ///
    /// Note on the past: a presentation scheduled for a day that has come and
    /// gone without being given still counts as `.scheduled`, matching today's
    /// behaviour — the calendar keeps showing it on its day, and "missed" is
    /// handled separately by `PresentationsMissWindow`. Promoting a missed
    /// presentation to `.attention` is a reasonable future change, but it is a
    /// behaviour change and belongs in its own commit.
    static func bucket(for presentation: PresentationTriageInput) -> TriageBucket {
        if presentation.state == .presented {
            return presentation.hasUnresolvedFollowUp ? .attention : .done
        }

        // The date decides, not the stored state. A draft that was given a day
        // is scheduled; a row marked `scheduled` that carries no day still has
        // to be planned. Either mismatch is possible after a CloudKit merge.
        return presentation.scheduledFor == nil ? .toSchedule : .scheduled
    }

    // MARK: Convenience

    /// True when the work item is waiting on the guide. This is the predicate
    /// the card badge and any "needs me" count should use.
    static func needsAttention(_ work: WorkTriageInput, asOf now: Date = Date()) -> Bool {
        bucket(for: work, asOf: now) == .attention
    }

    /// True when the presentation is waiting on the guide.
    static func needsAttention(_ presentation: PresentationTriageInput) -> Bool {
        bucket(for: presentation) == .attention
    }
}
