// ProgressionTypes.swift
// Shared value types for the Progression feature.

import SwiftUI

// MARK: - CDLesson Node Status

/// Status of a single lesson in a student's progression timeline: the Checklist's ladder
/// (`ChecklistDisplayStatus.resolve`), with a dated plan as `scheduled` and everything below
/// it as `notStarted`. See `resolve`.
enum LessonNodeStatus: Sendable, Equatable {
    case notStarted
    case scheduled(Date)
    case presented
    case practicing
    case reviewing
    /// A mastery mark on the child's `CDLessonPresentation`, never closed work alone.
    case mastered

    var color: Color {
        switch self {
        case .notStarted:   return .gray
        case .scheduled:    return .orange
        case .presented:    return .orange
        case .practicing:   return .blue
        case .reviewing:    return .yellow
        case .mastered:     return .green
        }
    }

    var iconName: String {
        switch self {
        case .notStarted:   return "circle"
        case .scheduled:    return "clock"
        case .presented:    return "circle.fill"
        case .practicing:   return "pencil.circle.fill"
        case .reviewing:    return "eye.circle.fill"
        case .mastered:     return "checkmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .notStarted:       return "Not Started"
        case .scheduled:        return "Scheduled"
        case .presented:        return "Presented"
        case .practicing:       return "Practicing"
        case .reviewing:        return "Reviewing"
        case .mastered:         return "Mastered"
        }
    }

    /// A lesson's status for one child, by the Checklist's rule.
    /// - Parameters:
    ///   - isPresented: The child has a presented assignment for the lesson.
    ///   - scheduledFor: The date of the child's planned (not yet presented) assignment;
    ///     nil when there is none or it waits undated in the Inbox.
    ///   - isMastered: The child has a mastery mark on the lesson
    ///     (`PresentationRecordIndex.masteryMarks`).
    ///   - workStatuses: The child's work on the lesson, open and closed.
    static func resolve(
        isPresented: Bool,
        scheduledFor: Date?,
        isMastered: Bool,
        workStatuses: [WorkStatus]
    ) -> LessonNodeStatus {
        let rung = ChecklistDisplayStatus.resolve(
            isMastered: isMastered,
            workStatuses: workStatuses,
            isPresented: isPresented,
            isPlanned: scheduledFor != nil
        )
        switch rung {
        case .mastered:   return .mastered
        case .reviewing:  return .reviewing
        case .practicing: return .practicing
        case .presented:  return .presented
        case .planned:    return scheduledFor.map(LessonNodeStatus.scheduled) ?? .notStarted
        case .ready, .notReady: return .notStarted
        }
    }
}

// MARK: - CDLesson Progression Node

/// A single lesson in a student's progression timeline, with nested work items.
struct LessonProgressionNode: Identifiable {
    let id: UUID
    let lesson: CDLesson
    let orderInSequence: Int
    let status: LessonNodeStatus
    let presentedAt: Date?
    let presentationID: UUID?
    let activeWork: [WorkProgressItem]
    let isNext: Bool
}

// MARK: - Work Progress Item

/// A work item attached to a lesson in the progression timeline.
struct WorkProgressItem: Identifiable {
    let id: UUID
    let work: CDWorkModel
    let status: WorkStatus
    let kind: WorkKind?
    let ageSchoolDays: Int
    let lastCheckIn: CDWorkCheckIn?
    let nextCheckIn: CDWorkCheckIn?
}
