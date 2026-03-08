// ProgressionTypes.swift
// Shared value types for the Progression feature.

import SwiftUI

// MARK: - Lesson Node Status

/// Status of a single lesson in a student's progression timeline.
enum LessonNodeStatus: Sendable {
    case notStarted
    case scheduled(Date)
    case presented
    case practicing
    case reviewing
    case completed

    var color: Color {
        switch self {
        case .notStarted:   return .gray
        case .scheduled:    return .orange
        case .presented:    return .orange
        case .practicing:   return .blue
        case .reviewing:    return .yellow
        case .completed:    return .green
        }
    }

    var iconName: String {
        switch self {
        case .notStarted:   return "circle"
        case .scheduled:    return "clock"
        case .presented:    return "circle.fill"
        case .practicing:   return "pencil.circle.fill"
        case .reviewing:    return "eye.circle.fill"
        case .completed:    return "checkmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .notStarted:       return "Not Started"
        case .scheduled:        return "Scheduled"
        case .presented:        return "Presented"
        case .practicing:       return "Practicing"
        case .reviewing:        return "Reviewing"
        case .completed:        return "Mastered"
        }
    }
}

// MARK: - Lesson Progression Node

/// A single lesson in a student's progression timeline, with nested work items.
struct LessonProgressionNode: Identifiable {
    let id: UUID
    let lesson: Lesson
    let orderInGroup: Int
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
    let work: WorkModel
    let status: WorkStatus
    let kind: WorkKind?
    let ageSchoolDays: Int
    let lastCheckIn: WorkCheckIn?
    let nextCheckIn: WorkCheckIn?
}

// MARK: - Group Summary

/// Summary data for a subject/group card on the landing page.
struct GroupSummary: Identifiable, Sendable {
    let id: String
    let subject: String
    let group: String
    let lessonCount: Int
    let studentCount: Int
    let activeWorkCount: Int
    let studentsReadyForNext: Int
    let studentsNeedingAttention: Int
    let furthestLessonName: String?
}
