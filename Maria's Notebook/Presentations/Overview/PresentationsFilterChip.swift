// PresentationsFilterChip.swift
// Segmented filter for the "Ready to Present" section: prioritized slices
// of the inbox the guide can hop between when planning the week.

import SwiftUI

enum PresentationsFilterChip: String, CaseIterable, Identifiable, Sendable {
    case all
    case suggestedNext
    case waitingForWork
    case overdue
    case recentlyMissed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .suggestedNext: return "Suggested Next"
        case .waitingForWork: return "Brewing"
        case .overdue: return "Overdue"
        case .recentlyMissed: return "Recently Missed"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
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
        case .suggestedNext: return Color.accentColor
        case .waitingForWork: return Color.secondary
        case .overdue: return AppColors.color(for: .overdue)
        case .recentlyMissed: return AppColors.attention
        }
    }
}
