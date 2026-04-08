// FridayReviewTypes.swift
// Value types for the Friday Review Ritual feature.

import SwiftUI

struct WeekSummary: Sendable {
    let presentationsGiven: Int
    let notesRecorded: Int
    let workCompleted: Int
    let weekStart: Date
    let weekEnd: Date
}

struct UnobservedStudent: Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let nickname: String?
    let level: CDStudent.Level
    let daysSinceLastNote: Int?

    var displayName: String { nickname ?? firstName }
}

struct FollowUpItem: Identifiable, Sendable {
    let id: UUID
    let lessonTitle: String
    let studentNames: [String]
    let presentedAt: Date
    let needsPractice: Bool
    let needsAnotherPresentation: Bool
}

struct StaleWorkItem: Identifiable, Sendable {
    let id: UUID
    let title: String
    let studentName: String
    let status: WorkStatus
    let lastTouchedAt: Date?
    let daysSinceTouch: Int
}

struct MondayPriority: Identifiable, Sendable {
    let id: String
    let priorityType: PriorityType
    let title: String
    let detail: String
    let urgency: Int
}

enum PriorityType: String, Sendable {
    case unobserved
    case staleWork
    case followUp

    var icon: String {
        switch self {
        case .unobserved: return "eye.slash"
        case .staleWork: return "clock.badge.exclamationmark"
        case .followUp: return "arrow.uturn.forward"
        }
    }

    var color: Color {
        switch self {
        case .unobserved: return AppColors.warning
        case .staleWork: return AppColors.destructive
        case .followUp: return .blue
        }
    }
}
