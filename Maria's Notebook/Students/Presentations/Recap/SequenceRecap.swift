// SequenceRecap.swift
// Sendable snapshot types describing every lesson, presentation, work item,
// and note for each student in the current presentation, scoped to the
// curriculum sequence of the lesson the user is currently editing.
//
// Built on the main actor by SequenceRecapResolver and rendered by
// SequenceRecapSection. Values are immutable and Sendable so SwiftUI views
// can hold them in @State without dragging in NSManagedObject references.

import Foundation

// MARK: - Top Level

struct SequenceRecap: Sendable, Equatable {
    let sequenceName: String
    let area: String
    /// All lessons in the sequence (including the current one), sorted by `orderInSequence` then name.
    let lessonsInSequence: [SequenceRecapLesson]
    /// One entry per student in the current presentation.
    let studentEntries: [SequenceRecapStudentEntry]
}

struct SequenceRecapLesson: Sendable, Equatable, Identifiable {
    let id: UUID                 // CDLesson.id
    let name: String
    let orderInSequence: Int
    /// True for the lesson the user is currently editing.
    let isCurrent: Bool
}

// MARK: - Per-Student

struct SequenceRecapStudentEntry: Sendable, Equatable, Identifiable {
    let id: UUID                 // CDStudent.id
    let studentName: String
    /// One entry per lesson in the sequence, in `lessonsInSequence` order.
    let lessonEntries: [SequenceRecapLessonEntry]
    /// Notes linked to a lesson in the sequence AND to this student that didn't
    /// land in any specific bucket below (defensive catch-all).
    let orphanNotes: [SequenceRecapNote]
}

struct SequenceRecapLessonEntry: Sendable, Equatable, Identifiable {
    let id: UUID                 // CDLesson.id (stable per row inside a student)
    let lessonName: String
    let isCurrentLesson: Bool

    /// nil ⇒ "Not yet presented" (no CDLessonPresentation row for this student).
    let outcomeState: LessonPresentationState?
    let firstPresentedAt: Date?
    let lastObservedAt: Date?
    let masteredAt: Date?

    /// Per-student lesson outcome notes (CDLessonPresentation.notes).
    let perStudentLessonNotes: String?

    /// Every CDLessonAssignment the student was part of for this lesson, newest first.
    let presentations: [SequenceRecapPresentation]
    /// CDWorkModel rows for this (student, lesson) whose `presentationID` doesn't match
    /// any presentation in `presentations` (manual follow-ups, or work whose parent
    /// assignment no longer includes this student). Newest first.
    let unattachedWorkItems: [SequenceRecapWorkItem]
    /// CDNote rows tied to (lessonID, this student) that aren't already attached
    /// to a presentation, work item, or check-in below.
    let directNotes: [SequenceRecapNote]

    /// True when there's literally nothing to show for this lesson (no presentation,
    /// no work, no notes, no outcome). The view renders "Not yet presented" for these.
    var isEmpty: Bool {
        outcomeState == nil
            && presentations.isEmpty
            && unattachedWorkItems.isEmpty
            && directNotes.isEmpty
            && (perStudentLessonNotes ?? "").isEmpty
    }
}

// MARK: - Presentations

struct SequenceRecapPresentation: Sendable, Equatable, Identifiable {
    let id: UUID                 // CDLessonAssignment.id
    let presentedAt: Date?
    let scheduledFor: Date?
    let state: LessonAssignmentState
    let needsPractice: Bool
    let needsAnotherPresentation: Bool
    /// Group-level teacher notes from CDLessonAssignment.notes.
    let groupNotes: String
    /// Free-form CDNote rows whose `lessonAssignment` relationship points at this assignment.
    let attachedNotes: [SequenceRecapNote]
    /// CDWorkModel rows whose `presentationID` matches this assignment and whose student
    /// is the recap student. Newest first.
    let workItems: [SequenceRecapWorkItem]
}

// MARK: - Work

struct SequenceRecapWorkItem: Sendable, Equatable, Identifiable {
    let id: UUID                 // CDWorkModel.id
    let title: String
    let kind: WorkKind?
    let status: WorkStatus
    let completionOutcome: CompletionOutcome?
    let assignedAt: Date?
    let completedAt: Date?
    /// Free-form CDNote rows whose `work` relationship points at this work item
    /// (excluding ones attached to a specific check-in below).
    let attachedNotes: [SequenceRecapNote]
    /// Newest first.
    let checkIns: [SequenceRecapCheckIn]
}

struct SequenceRecapCheckIn: Sendable, Equatable, Identifiable {
    let id: UUID                 // CDWorkCheckIn.id
    let date: Date?
    let status: WorkCheckInStatus
    let purpose: String
    /// CDNote rows whose `workCheckIn` relationship points at this check-in.
    let notes: [SequenceRecapNote]
}

// MARK: - Notes

struct SequenceRecapNote: Sendable, Equatable, Identifiable {
    let id: UUID                 // CDNote.id
    let body: String
    let createdAt: Date?
    /// CDNote.categoryRaw — kept as raw string so this file doesn't need to import the enum.
    let category: String
    let isPinned: Bool
}
