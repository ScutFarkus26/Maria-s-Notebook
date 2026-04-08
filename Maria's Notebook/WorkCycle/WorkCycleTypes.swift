// WorkCycleTypes.swift
// Enums and value types for the Work Cycle Tracker feature.

import SwiftUI

// MARK: - Enums

enum CycleStatus: String, Sendable, CaseIterable, Identifiable {
    case active
    case paused
    case completed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .completed: return "Completed"
        }
    }

    var color: Color {
        switch self {
        case .active: return AppColors.success
        case .paused: return AppColors.warning
        case .completed: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .active: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return SFSymbol.Action.checkmarkCircleFill
        }
    }
}

enum SocialMode: String, Sendable, CaseIterable, Identifiable {
    case independent
    case pair
    case smallGroup
    case largeGroup

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .independent: return "Independent"
        case .pair: return "Pair"
        case .smallGroup: return "Small Group"
        case .largeGroup: return "Large Group"
        }
    }

    var icon: String {
        switch self {
        case .independent: return "person"
        case .pair: return "person.2"
        case .smallGroup: return "person.3"
        case .largeGroup: return "person.3.sequence"
        }
    }
}

enum ConcentrationLevel: String, Sendable, CaseIterable, Identifiable {
    case deepFocus
    case focused
    case intermittent
    case wandering
    case disruptive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepFocus: return "Deep Focus"
        case .focused: return "Focused"
        case .intermittent: return "Intermittent"
        case .wandering: return "Wandering"
        case .disruptive: return "Disruptive"
        }
    }

    var color: Color {
        switch self {
        case .deepFocus: return AppColors.success
        case .focused: return .blue
        case .intermittent: return AppColors.warning
        case .wandering: return .orange
        case .disruptive: return AppColors.destructive
        }
    }

    var icon: String {
        switch self {
        case .deepFocus: return "brain.head.profile"
        case .focused: return "eye"
        case .intermittent: return "arrow.left.arrow.right"
        case .wandering: return "figure.walk"
        case .disruptive: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Value Types

struct StudentCycleCard: Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let nickname: String?
    let level: CDStudent.Level
    var currentActivity: String?
    var socialMode: SocialMode?
    var concentration: ConcentrationLevel?
    var entryCount: Int

    var displayName: String { nickname ?? firstName }
}

struct CycleSummary: Sendable {
    let duration: TimeInterval
    let totalEntries: Int
    let studentsTracked: Int
    let concentrationBreakdown: [ConcentrationLevel: Int]
    let socialModeBreakdown: [SocialMode: Int]
}
