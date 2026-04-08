// SmallGroupPlannerTypes.swift
// Value types for the Small Group Planning Intelligence feature.

import SwiftUI

// MARK: - Lesson Group Candidate

/// Represents a lesson that has potential students for a group presentation.
struct LessonGroupCandidate: Identifiable, Sendable {
    let id: UUID
    let lessonName: String
    let subject: String
    let group: String
    let orderInGroup: Int
    let readyStudents: [GroupStudentStatus]
    let almostReadyStudents: [GroupStudentStatus]
    let notReadyCount: Int
    let totalEnrolled: Int
    let precedingLessonName: String?

    var readyCount: Int { readyStudents.count }
    var almostReadyCount: Int { almostReadyStudents.count }
    var hasOpportunity: Bool { readyCount > 0 || almostReadyCount > 0 }
}

// MARK: - Student Status

/// A student's readiness status for a specific lesson.
struct GroupStudentStatus: Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let nickname: String?
    let level: CDStudent.Level
    let tier: ReadinessTier
    let blockingReasons: [GroupBlockingReason]
    let precedingLessonName: String?

    var displayName: String { nickname ?? firstName }

    var initials: String {
        let first = firstName.prefix(1)
        let last = lastName.prefix(1)
        return "\(first)\(last)".uppercased()
    }
}

// MARK: - Readiness Tier

enum ReadinessTier: String, Sendable, CaseIterable, Identifiable {
    case ready
    case almostReady
    case notReady

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .almostReady: return "Almost Ready"
        case .notReady: return "Not Ready"
        }
    }

    var color: Color {
        switch self {
        case .ready: return AppColors.success
        case .almostReady: return AppColors.warning
        case .notReady: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .ready: return SFSymbol.Action.checkmarkCircleFill
        case .almostReady: return "clock.badge.exclamationmark"
        case .notReady: return "minus.circle"
        }
    }
}

// MARK: - Blocking Reason

/// Specific reason a student is not yet ready for a lesson.
enum GroupBlockingReason: Sendable, Identifiable {
    case needsPracticeCompletion(workTitle: String, workID: UUID, daysSinceAssigned: Int)
    case needsTeacherConfirmation(precedingLessonName: String, assignmentID: UUID)
    case needsPrecedingPresentation(lessonName: String)

    var id: String {
        switch self {
        case .needsPracticeCompletion(_, let wid, _): return "practice-\(wid)"
        case .needsTeacherConfirmation(_, let aid): return "confirm-\(aid)"
        case .needsPrecedingPresentation(let name): return "preceding-\(name)"
        }
    }

    var icon: String {
        switch self {
        case .needsPracticeCompletion: return "tray.full"
        case .needsTeacherConfirmation: return "person.badge.shield.checkmark"
        case .needsPrecedingPresentation: return SFSymbol.Education.book
        }
    }

    var color: Color {
        switch self {
        case .needsPracticeCompletion: return .blue
        case .needsTeacherConfirmation: return .purple
        case .needsPrecedingPresentation: return .orange
        }
    }

    var summary: String {
        switch self {
        case .needsPracticeCompletion(let title, _, let days):
            return "Complete: \(title) (\(days)d ago)"
        case .needsTeacherConfirmation(let lessonName, _):
            return "Confirm: \(lessonName)"
        case .needsPrecedingPresentation(let lessonName):
            return "Needs: \(lessonName)"
        }
    }

    /// Whether this reason has an actionable button (e.g., one-tap confirm).
    var isActionable: Bool {
        if case .needsTeacherConfirmation = self { return true }
        return false
    }
}
