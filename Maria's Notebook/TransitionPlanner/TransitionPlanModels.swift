// TransitionPlanModels.swift
// Enums and templates for student transition planning.

import Foundation
import SwiftUI

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
