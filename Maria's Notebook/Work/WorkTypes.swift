// WorkTypes.swift
// Shared enums for work-related data models

import Foundation
import SwiftUI

// MARK: - Work Kind
/// Describes the type of work assignment
public enum WorkKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case practiceLesson
    case followUpAssignment
    case research
    case report

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .practiceLesson: return "Practice"
        case .followUpAssignment: return "Follow-Up"
        case .research: return "Project"
        case .report: return "Report"
        }
    }
}

// MARK: - Work Status
/// Describes the lifecycle status of a work item
public enum WorkStatus: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case active
    case review
    case complete

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .review: return "Review"
        case .complete: return "Complete"
        }
    }
}

// MARK: - Completion Outcome
/// Describes the outcome when work is completed
public enum CompletionOutcome: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case mastered
    case needsMorePractice
    case needsReview
    case incomplete
    case notApplicable

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mastered: return "Mastered"
        case .needsMorePractice: return "Keep Practicing"
        case .needsReview: return "Needs Review"
        case .incomplete: return "Incomplete"
        case .notApplicable: return "N/A"
        }
    }
}

// MARK: - Scheduled Reason
/// Describes why a work item was scheduled
public enum ScheduledReason: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case checkIn
    case due
    case followUp
    case assessment
    case studentRequest
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .checkIn: return "Check-In"
        case .due: return "Due"
        case .followUp: return "Follow Up"
        case .assessment: return "Assessment"
        case .studentRequest: return "Student Request"
        case .other: return "Other"
        }
    }
}

// MARK: - Work Source Context Type
/// Describes the source context from which work was created
public enum WorkSourceContextType: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case projectSession
    case bookClubSession
    case presentation
    case lesson
    case manual

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .projectSession: return "Project Session"
        case .bookClubSession: return "Book Club Session"
        case .presentation: return "Presentation"
        case .lesson: return "Lesson"
        case .manual: return "Manual"
        }
    }
}

// MARK: - WorkKind Styling

public extension WorkKind {
    /// Standard color for this work kind used throughout the app
    var color: Color {
        switch self {
        case .practiceLesson: return .purple
        case .followUpAssignment: return .orange
        case .research: return .teal
        case .report: return .green
        }
    }

    /// System icon name for this work kind
    var iconName: String {
        switch self {
        case .practiceLesson: return "pencil.circle"
        case .followUpAssignment: return "arrow.uturn.forward.circle"
        case .research: return "magnifyingglass.circle"
        case .report: return "doc.text"
        }
    }

    /// Short label suitable for compact displays
    var shortLabel: String {
        switch self {
        case .practiceLesson: return "Practice"
        case .followUpAssignment: return "Follow-Up"
        case .research: return "Project"
        case .report: return "Report"
        }
    }

}

// MARK: - WorkKind to WorkType Conversion (Internal)

extension WorkKind {
    /// Convert to legacy WorkModel.WorkType for backward compatibility
    var asWorkType: WorkModel.WorkType {
        switch self {
        case .practiceLesson: return .practice
        case .followUpAssignment: return .followUp
        case .research: return .research
        case .report: return .report
        }
    }
}

// MARK: - WorkStatus Styling

public extension WorkStatus {
    /// Standard color for this status
    var color: Color {
        switch self {
        case .active: return .blue
        case .review: return .orange
        case .complete: return .green
        }
    }

    /// System icon name for this status
    var iconName: String {
        switch self {
        case .active: return "circle"
        case .review: return "eye.circle"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

// MARK: - CompletionOutcome Styling

public extension CompletionOutcome {
    /// Standard color for this outcome
    var color: Color {
        switch self {
        case .mastered: return .green
        case .needsMorePractice: return .orange
        case .needsReview: return .yellow
        case .incomplete: return .red
        case .notApplicable: return .gray
        }
    }

    /// System icon name for this outcome
    var iconName: String {
        switch self {
        case .mastered: return "star.fill"
        case .needsMorePractice: return "arrow.clockwise"
        case .needsReview: return "eye"
        case .incomplete: return "xmark.circle"
        case .notApplicable: return "minus.circle"
        }
    }
}
