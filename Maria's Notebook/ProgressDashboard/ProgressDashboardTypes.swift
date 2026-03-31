// ProgressDashboardTypes.swift
// Value types for the Progress Dashboard view layer.

import Foundation

/// One student's complete dashboard data.
struct StudentDashboardCard: Identifiable {
    let id: UUID
    let firstName: String
    let lastName: String
    let nickname: String?
    let level: CDStudent.Level
    let categories: [StudentCategoryProgress]

    var displayName: String {
        nickname ?? firstName
    }
}

/// A single subject+group row for one student.
struct StudentCategoryProgress: Identifiable {
    let id: String // "\(studentID)|\(subject)|\(group)"
    let subject: String
    let group: String
    let previousLesson: PreviousLessonSummary?
    let openWork: [OpenWorkSummary]
    let nextLesson: NextLessonInfo?
}

/// Lightweight reference to the most recently presented lesson.
struct PreviousLessonSummary: Identifiable {
    let id: UUID
    let lessonID: UUID
    let name: String
    let presentedAt: Date
    let assignmentID: UUID
}

/// Lightweight reference to an open work item.
struct OpenWorkSummary: Identifiable {
    let id: UUID
    let title: String
    let kind: WorkKind?
    let status: WorkStatus
    let ageSchoolDays: Int
}

/// Info about the next lesson in the sequence.
struct NextLessonInfo: Identifiable {
    let id: UUID
    let name: String
    let state: NextLessonState
    let assignmentID: UUID?
}

/// Whether the next lesson is already planned.
enum NextLessonState {
    case notPlanned
    case inInbox
    case scheduled(Date)
}
