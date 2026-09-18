// ProgressDashboardTypes.swift
// Value types for the per-student progression map view.
//
// Hierarchy: Student → Subject (lesson.area) → Sequence (lesson.sequence) → Lesson pills.
// Each pill carries a progression status (notStarted, scheduled, presented, etc.)
// so the row mirrors the visual style of LessonsScopeMapView but pivots on the student.

import Foundation

/// One student's full progression map across every subject they've started.
struct StudentProgressionCard: Identifiable {
    let id: UUID  // studentID
    let firstName: String
    let lastName: String
    let nickname: String?
    let level: CDStudent.Level
    let subjects: [SubjectProgression]

    var displayName: String { nickname ?? firstName }
    var fullName: String { "\(firstName) \(lastName)" }

    /// Total number of (subject, sequence) threads visible for this student.
    var sequenceCount: Int { subjects.reduce(0) { $0 + $1.sequences.count } }
}

/// A subject (lesson.area) that a student has started, grouping all their active sequences inside it.
struct SubjectProgression: Identifiable {
    let id: String  // "\(studentID)|\(area)"
    let area: String
    let sequences: [SequenceProgression]
}

/// A sequence (lesson.sequence) that a student has started, with the ordered list of lesson pills.
struct SequenceProgression: Identifiable {
    let id: String  // "\(studentID)|\(area)|\(sequence)"
    let studentID: UUID
    let area: String
    let sequence: String
    let pills: [LessonPillState]

    var presentedCount: Int {
        pills.filter { $0.isPresentedOrBeyond }.count
    }

    var totalCount: Int { pills.count }
}

/// One lesson rendered as a pill in a student's sequence row.
struct LessonPillState: Identifiable {
    let id: UUID  // lessonID
    let lessonID: UUID
    let name: String
    let status: LessonNodeStatus
    let orderInSequence: Int

    /// True once the lesson has been presented (presented / practicing / reviewing / completed).
    var isPresentedOrBeyond: Bool {
        switch status {
        case .presented, .practicing, .reviewing, .completed: return true
        case .notStarted, .scheduled: return false
        }
    }
}
