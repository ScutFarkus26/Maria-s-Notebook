// TransitionPlanModels.swift
// SwiftData models for student transition planning.

import Foundation
import SwiftData
import SwiftUI

// MARK: - TransitionPlan

@Model
final class TransitionPlan: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var studentID: String = ""
    var fromLevelRaw: String = "Lower Elementary"
    var toLevelRaw: String = "Upper Elementary"
    var statusRaw: String = TransitionStatus.notStarted.rawValue
    var targetDate: Date?
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \TransitionChecklistItem.transitionPlan)
    var checklistItems: [TransitionChecklistItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \Note.transitionPlan)
    var observationNotes: [Note]? = []

    var studentUUID: UUID? {
        UUID(uuidString: studentID)
    }

    var status: TransitionStatus {
        get { TransitionStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        studentID: String = "",
        fromLevelRaw: String = "Lower Elementary",
        toLevelRaw: String = "Upper Elementary",
        status: TransitionStatus = .notStarted,
        targetDate: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.studentID = studentID
        self.fromLevelRaw = fromLevelRaw
        self.toLevelRaw = toLevelRaw
        self.statusRaw = status.rawValue
        self.targetDate = targetDate
        self.notes = notes
    }
}

// MARK: - TransitionChecklistItem

@Model
final class TransitionChecklistItem: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var transitionPlanID: String = ""
    var transitionPlan: TransitionPlan?
    var title: String = ""
    var categoryRaw: String = ChecklistCategory.academic.rawValue
    var isCompleted: Bool = false
    var completedAt: Date?
    var sortOrder: Int = 0
    var notes: String = ""

    var category: ChecklistCategory {
        get { ChecklistCategory(rawValue: categoryRaw) ?? .academic }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        transitionPlanID: String = "",
        title: String = "",
        category: ChecklistCategory = .academic,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.transitionPlanID = transitionPlanID
        self.title = title
        self.categoryRaw = category.rawValue
        self.sortOrder = sortOrder
    }
}

// MARK: - Enums

enum TransitionStatus: String, CaseIterable, Identifiable {
    case notStarted
    case inProgress
    case ready
    case transitioned

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .ready: return "Ready"
        case .transitioned: return "Transitioned"
        }
    }

    var icon: String {
        switch self {
        case .notStarted: return "circle"
        case .inProgress: return "arrow.forward.circle"
        case .ready: return "checkmark.circle"
        case .transitioned: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notStarted: return .secondary
        case .inProgress: return .blue
        case .ready: return .orange
        case .transitioned: return .green
        }
    }
}

enum ChecklistCategory: String, CaseIterable, Identifiable {
    case academic
    case social
    case independence
    case executive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .academic: return "Academic"
        case .social: return "Social"
        case .independence: return "Independence"
        case .executive: return "Executive Function"
        }
    }

    var icon: String {
        switch self {
        case .academic: return "book"
        case .social: return "person.2"
        case .independence: return "figure.stand"
        case .executive: return "brain"
        }
    }

    var color: Color {
        switch self {
        case .academic: return .blue
        case .social: return .green
        case .independence: return .orange
        case .executive: return .purple
        }
    }
}

// MARK: - Default Checklist Templates

enum TransitionChecklistTemplates {
    static let lowerToUpper: [(title: String, category: ChecklistCategory)] = [
        // Academic
        ("Confident with 4 operations", .academic),
        ("Independent reading", .academic),
        ("Research skills emerging", .academic),
        ("Can write multi-paragraph compositions", .academic),

        // Social
        ("Seeks peer collaboration", .social),
        ("Can resolve conflicts with guidance", .social),
        ("Shows group leadership", .social),
        ("Participates in going-out planning", .social),

        // Independence
        ("Self-directed work cycle (2+ hours)", .independence),
        ("Manages materials independently", .independence),
        ("Plans own work schedule", .independence),
        ("Uses control of error", .independence),

        // Executive
        ("Can plan multi-step projects", .executive),
        ("Time awareness and planning", .executive),
        ("Self-assessment capability", .executive),
        ("Organizes workspace independently", .executive)
    ]
}
