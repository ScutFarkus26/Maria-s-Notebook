// WorkTypes.swift
// Shared enums for work-related data models

import Foundation
import SwiftUI

// MARK: - Work Kind
/// Describes the type of work assignment
public enum WorkKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case practiceLesson
    case followUpAssignment
    case research

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .practiceLesson: return "Practice"
        case .followUpAssignment: return "Follow-Up"
        case .research: return "Project"
        }
    }
}

// MARK: - Work Status
/// Describes the lifecycle status of a work item
public enum WorkStatus: String, Codable, CaseIterable, Hashable, Identifiable {
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
public enum CompletionOutcome: String, Codable, CaseIterable, Hashable, Identifiable {
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
public enum ScheduledReason: String, Codable, CaseIterable, Hashable, Identifiable {
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
public enum WorkSourceContextType: String, Codable, CaseIterable, Hashable, Identifiable {
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
