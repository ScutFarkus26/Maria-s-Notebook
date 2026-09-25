// WorkTypes.swift
// Shared enums for work-related data models

import Foundation
import SwiftUI

// MARK: - Work Kind
/// Describes the type of work assignment
nonisolated public enum WorkKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
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
/// The one verdict a work row carries, per child.
///
/// Until 2026-09-15 a row had a lifecycle status (active / review / complete)
/// *and* a completion outcome (mastered / keep practicing / …) that were only
/// ever set together. They are one field now. Two states are open and keep
/// the work on the guide's radar; the rest close it, log it, and clear its
/// check-ins from the Scheduled strip. `done` keeps the legacy raw value
/// `"complete"` so rows closed before the merge need no rewrite; it is never
/// offered in a picker.
nonisolated public enum WorkStatus: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    // Open
    /// The child is working on it.
    case active
    /// The guide needs to look at it before it can move on.
    case review
    // Closed
    case mastered
    case keepPracticing
    case incomplete
    /// Closed with no verdict — legacy rows, raw value `"complete"`.
    case done = "complete"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .active: return "Working"
        case .review: return "Needs Review"
        case .mastered: return "Mastered"
        case .keepPracticing: return "Keep Practicing"
        case .incomplete: return "Incomplete"
        case .done: return "Done"
        }
    }

    /// Still on the guide's radar.
    public var isOpen: Bool { self == .active || self == .review }
    /// Logged and off the Scheduled strip.
    public var isClosed: Bool { !isOpen }

    /// The statuses a picker offers. `done` is legacy only.
    public static let pickable: [WorkStatus] = [.active, .review, .mastered, .keepPracticing, .incomplete]
    public static let openCases: [WorkStatus] = allCases.filter(\.isOpen)
    public static let closedCases: [WorkStatus] = allCases.filter(\.isClosed)
    public static let openRawValues: [String] = openCases.map(\.rawValue)
    public static let closedRawValues: [String] = closedCases.map(\.rawValue)

    /// `statusRaw IN {open raws}` — the one spelling of "open work" for a fetch.
    public static var openPredicate: NSPredicate {
        NSPredicate(format: "statusRaw IN %@", openRawValues)
    }
}

// MARK: - Completion Outcome
/// The outcome of one *step* of a work item (`CDWorkStep.completionOutcome`).
///
/// A work row no longer carries one: its `completionOutcomeRaw` column is a
/// legacy field that `WorkStatusMigration` folds into `WorkStatus` and nothing
/// else reads.
nonisolated public enum CompletionOutcome: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case proficient = "mastered"
    case needsMorePractice
    case needsReview
    case incomplete
    case notApplicable

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .proficient: return "Mastered"
        case .needsMorePractice: return "Keep Practicing"
        case .needsReview: return "Needs Review"
        case .incomplete: return "Incomplete"
        case .notApplicable: return "N/A"
        }
    }
}

// MARK: - Work Source Context Type
/// Describes the source context from which work was created
nonisolated public enum WorkSourceContextType: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
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

// MARK: - Check-In Style
/// Describes how check-ins for multi-student work should be displayed and managed
nonisolated public enum CheckInStyle: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    /// Check each student one-on-one
    case individual
    /// Check all students together as a sequence
    case group
    /// Grouped display by default, expandable to individual rows
    case flexible

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .individual: return "Individual"
        case .group: return "Group"
        case .flexible: return "Flexible"
        }
    }

    public var iconName: String {
        switch self {
        case .individual: return "person.fill"
        case .group: return "person.3.fill"
        case .flexible: return "rectangle.expand.vertical"
        }
    }

    public var color: Color {
        switch self {
        case .individual: return .blue
        case .group: return .purple
        case .flexible: return .teal
        }
    }

    public var shortDescription: String {
        switch self {
        case .individual: return "Check in with each student separately"
        case .group: return "Check in with all students together"
        case .flexible: return "Grouped by default, expand to individual"
        }
    }
}

// MARK: - WorkKind Styling

nonisolated public extension WorkKind {
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

// MARK: - WorkStatus Styling

nonisolated public extension WorkStatus {
    /// Standard color for this status
    var color: Color {
        switch self {
        case .active: return .blue
        case .review: return .orange
        case .mastered: return .green
        case .keepPracticing: return .orange
        case .incomplete: return .red
        case .done: return .gray
        }
    }

    /// System icon name for this status
    var iconName: String {
        switch self {
        case .active: return "circle"
        case .review: return "eye.circle"
        case .mastered: return "star.fill"
        case .keepPracticing: return "arrow.clockwise"
        case .incomplete: return "xmark.circle"
        case .done: return "checkmark.circle.fill"
        }
    }
}

// MARK: - CompletionOutcome Styling

nonisolated public extension CompletionOutcome {
    /// Standard color for this outcome
    var color: Color {
        switch self {
        case .proficient: return .green
        case .needsMorePractice: return .orange
        case .needsReview: return .yellow
        case .incomplete: return .red
        case .notApplicable: return .gray
        }
    }

    /// System icon name for this outcome
    var iconName: String {
        switch self {
        case .proficient: return "star.fill"
        case .needsMorePractice: return "arrow.clockwise"
        case .needsReview: return "eye"
        case .incomplete: return "xmark.circle"
        case .notApplicable: return "minus.circle"
        }
    }
}
