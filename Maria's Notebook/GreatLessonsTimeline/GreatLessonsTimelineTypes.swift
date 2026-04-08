// GreatLessonsTimelineTypes.swift
// Value types for the Five Great Lessons Timeline feature.
// Maps lessons to cosmic education themes and tracks per-student progress.

import Foundation
import SwiftUI

/// A single Great Lesson branch with aggregated lesson and student data.
struct GreatLessonBranch: Identifiable, Sendable {
    let id: String
    let greatLesson: GreatLesson
    let totalLessons: Int
    let subjectGroups: [BranchSubjectGroup]
    let studentProgress: [StudentBranchProgress]

    /// Overall completion rate across all students (0.0–1.0).
    var overallCompletionRate: Double {
        guard !studentProgress.isEmpty else { return 0 }
        let total = studentProgress.reduce(0.0) { $0 + $1.completionPercentage }
        return total / Double(studentProgress.count)
    }

    /// Number of students who have at least one presentation in this branch.
    var studentsWithPresentations: Int {
        studentProgress.filter { $0.presentedCount > 0 }.count
    }

    /// Total active work items across all students in this branch.
    var totalActiveWork: Int {
        studentProgress.reduce(0) { $0 + $1.activeWorkCount }
    }

    /// Students with zero presentations in this branch.
    var studentsWithGaps: Int {
        studentProgress.filter { $0.presentedCount == 0 }.count
    }
}

/// A subject/group pair within a Great Lesson branch.
struct BranchSubjectGroup: Identifiable, Sendable {
    let id: String
    let subject: String
    let group: String
    let lessons: [BranchLesson]
}

/// A single lesson within a branch.
struct BranchLesson: Identifiable, Sendable {
    let id: UUID
    let name: String
    let isExplicitlyTagged: Bool
}

/// Per-student progress within a Great Lesson branch.
struct StudentBranchProgress: Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let level: CDStudent.Level
    let presentedCount: Int
    let totalLessons: Int
    let activeWorkCount: Int
    let lastPresentedAt: Date?
    let completionPercentage: Double
    let gapSubjects: [String]

    var displayName: String { firstName }
    var initials: String { "\(firstName.prefix(1))\(lastName.prefix(1))" }
}
