// PresentationsFilterChip.swift
// Filter pills for the Presentations half of the Lessons & Work workspace:
// prioritized slices of the inbox the guide can hop between when planning.
//
// `.followUp` is the one slice that is not about planning. It holds lessons
// already given that still carry an unresolved responsibility — observe the
// child, or decide what comes next. That list used to be the "Observe or
// Decide" section of the workspace's Attention tab; with kind as the top-level
// axis it belongs here, beside the other presentation states, rather than in a
// tab shared with children's work.

import SwiftUI

nonisolated enum PresentationsFilterChip: String, CaseIterable, Identifiable, Sendable, WorkspaceFilterChip {
    case all
    /// Given, and still waiting on the guide to observe or decide.
    case followUp
    case suggestedNext
    case waitingForWork
    case overdue
    case recentlyMissed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .followUp: return "Follow Up"
        case .suggestedNext: return "Suggested Next"
        case .waitingForWork: return "Brewing"
        case .overdue: return "Overdue"
        case .recentlyMissed: return "Recently Missed"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .followUp: return "eye.circle"
        case .suggestedNext: return "sparkles"
        case .waitingForWork: return "hourglass"
        case .overdue: return "clock.badge.exclamationmark"
        case .recentlyMissed: return "person.slash"
        }
    }

    /// Accent colour for the chip, sourced from the status ramp so it stays
    /// visually consistent with card borders, icons, and the header legend.
    var accent: Color {
        switch self {
        case .all: return .secondary
        case .followUp: return AppColors.info
        case .suggestedNext: return Color.accentColor
        case .waitingForWork: return Color.secondary
        case .overdue: return AppColors.color(for: .overdue)
        case .recentlyMissed: return AppColors.attention
        }
    }
}
