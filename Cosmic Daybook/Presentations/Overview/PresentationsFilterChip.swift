// PresentationsFilterChip.swift
// What the Presentations half of the Lessons & Work workspace is showing: one
// of three states, optionally narrowed by a flag.
//
// The half used to offer six pills side by side — All, Follow Up, Suggested
// Next, Brewing, Overdue, Recently Missed — whose counts could not add up,
// because they were not one kind of thing. Three are states a lesson is in
// (ready to give, brewing on the children's work, given and waiting on a
// follow-up) and every lesson is in exactly one of them; the other three are
// flags on ready lessons. So the states are a segmented control and the flags
// are toggles beside it (`ReadyToPresentFilterBar`), while the selection stays
// this one value: a flag is a narrower view of Ready, never a fourth state.
//
// `.followUp` is the one state that is not about planning. It holds lessons
// already given that still carry an unresolved responsibility — observe the
// child, or decide what comes next. That list used to be the "Observe or
// Decide" section of the workspace's Attention tab; with kind as the top-level
// axis it belongs here, beside the other presentation states, rather than in a
// tab shared with children's work.

import SwiftUI

nonisolated enum PresentationsFilterChip: String, CaseIterable, Identifiable, Sendable, WorkspaceFilterChip {
    /// Ready to give: unscheduled, and nothing in the children's work holds it
    /// back. The default, and where tapping an active flag returns to.
    case ready
    /// Given, and still waiting on the guide to observe or decide.
    case followUp
    case suggestedNext
    case waitingForWork
    case overdue
    case recentlyMissed

    /// The state segments, in the order the control draws them.
    static let segments: [PresentationsFilterChip] = [.ready, .waitingForWork, .followUp]

    /// The flag toggles beside the segments.
    static let flags: [PresentationsFilterChip] = [.overdue, .recentlyMissed, .suggestedNext]

    var id: String { rawValue }

    /// The segment that shows selected for this chip: a flag narrows Ready, so
    /// Ready stays lit while one is on.
    var segment: PresentationsFilterChip {
        switch self {
        case .ready, .overdue, .recentlyMissed, .suggestedNext: return .ready
        case .waitingForWork: return .waitingForWork
        case .followUp: return .followUp
        }
    }

    var isFlag: Bool { Self.flags.contains(self) }

    /// Where tapping this flag goes from `current`: on, or back to Ready when
    /// it is already on — the one way off, so no separate clear button.
    func flagTapped(from current: PresentationsFilterChip) -> PresentationsFilterChip {
        current == self ? .ready : self
    }

    var title: String {
        switch self {
        case .ready: return "Ready"
        case .followUp: return "Follow Up"
        case .suggestedNext: return "Suggest"
        case .waitingForWork: return "Brewing"
        case .overdue: return "Overdue"
        case .recentlyMissed: return "Missed"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "checkmark.circle"
        case .followUp: return "eye.circle"
        case .suggestedNext: return "sparkles"
        case .waitingForWork: return "hourglass"
        case .overdue: return "clock.badge.exclamationmark"
        case .recentlyMissed: return "person.slash"
        }
    }

    /// Accent color for the chip, sourced from the status ramp so it stays
    /// visually consistent with card borders, icons, and the header legend.
    var accent: Color {
        switch self {
        case .ready: return .secondary
        case .followUp: return AppColors.info
        case .suggestedNext: return Color.accentColor
        case .waitingForWork: return Color.secondary
        case .overdue: return AppColors.color(for: .overdue)
        case .recentlyMissed: return AppColors.attention
        }
    }
}
