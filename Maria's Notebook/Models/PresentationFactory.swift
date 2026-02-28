//
//  PresentationFactory.swift
//  Maria's Notebook
//
//  Centralizes LessonAssignment creation to eliminate duplicated initialization logic.
//  Factory for creating LessonAssignment (Presentation) instances.
//

import Foundation
import SwiftData

enum PresentationFactory {

    // MARK: - Draft (Inbox)

    /// Creates a draft LessonAssignment (appears in inbox).
    /// Use when creating a new lesson that hasn't been scheduled yet.
    static func makeDraft(
        lessonID: UUID,
        studentIDs: [UUID],
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> LessonAssignment {
        LessonAssignment(
            id: id,
            createdAt: createdAt,
            state: .draft,
            scheduledFor: nil,
            presentedAt: nil,
            lessonID: lessonID,
            studentIDs: studentIDs,
            lesson: nil,
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: "",
            notes: "",
            trackID: nil,
            trackStepID: nil,
            manuallyUnblocked: false
        )
    }

    /// Creates a draft LessonAssignment with relationship objects.
    static func makeDraft(
        lesson: Lesson,
        students: [Student],
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> LessonAssignment {
        LessonAssignment(
            id: id,
            lesson: lesson,
            students: students,
            state: .draft,
            scheduledFor: nil
        )
    }

    // MARK: - Scheduled

    /// Creates a scheduled LessonAssignment for a specific date/time.
    static func makeScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> LessonAssignment {
        LessonAssignment(
            id: id,
            createdAt: createdAt,
            state: .scheduled,
            scheduledFor: scheduledFor,
            presentedAt: nil,
            lessonID: lessonID,
            studentIDs: studentIDs,
            lesson: nil,
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: "",
            notes: "",
            trackID: nil,
            trackStepID: nil,
            manuallyUnblocked: false
        )
    }

    /// Creates a scheduled LessonAssignment with relationship objects.
    static func makeScheduled(
        lesson: Lesson,
        students: [Student],
        scheduledFor: Date,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> LessonAssignment {
        LessonAssignment(
            id: id,
            lesson: lesson,
            students: students,
            state: .scheduled,
            scheduledFor: scheduledFor
        )
    }

    // MARK: - Presented/Given

    /// Creates a LessonAssignment marked as presented.
    /// Use when marking a lesson as complete.
    static func makePresented(
        lessonID: UUID,
        studentIDs: [UUID],
        presentedAt: Date = Date(),
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> LessonAssignment {
        LessonAssignment(
            id: id,
            createdAt: createdAt,
            state: .presented,
            scheduledFor: nil,
            presentedAt: presentedAt,
            lessonID: lessonID,
            studentIDs: studentIDs,
            lesson: nil,
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: "",
            notes: "",
            trackID: nil,
            trackStepID: nil,
            manuallyUnblocked: false
        )
    }

    /// Creates a presented LessonAssignment with relationship objects.
    static func makePresented(
        lesson: Lesson,
        students: [Student],
        presentedAt: Date = Date(),
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> LessonAssignment {
        let la = LessonAssignment(
            id: id,
            lesson: lesson,
            students: students,
            state: .presented,
            scheduledFor: nil
        )
        la.presentedAt = presentedAt
        return la
    }

    // MARK: - Helpers

    /// Attaches relationship objects to an existing LessonAssignment.
    /// Useful when you create with IDs but need to attach resolved objects later.
    static func attachRelationships(
        to lessonAssignment: LessonAssignment,
        lesson: Lesson?,
        students: [Student]
    ) {
        lessonAssignment.lesson = lesson
        lessonAssignment.students = students
        lessonAssignment.syncSnapshotsFromRelationships()
    }

    // MARK: - Insert Helpers (for convenience)

    /// Creates and inserts a draft LessonAssignment.
    @MainActor
    static func insertDraft(
        lessonID: UUID,
        studentIDs: [UUID],
        context: ModelContext
    ) -> LessonAssignment {
        let la = makeDraft(lessonID: lessonID, studentIDs: studentIDs)
        context.insert(la)
        return la
    }

    /// Creates and inserts a scheduled LessonAssignment.
    @MainActor
    static func insertScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date,
        context: ModelContext
    ) -> LessonAssignment {
        let la = makeScheduled(lessonID: lessonID, studentIDs: studentIDs, scheduledFor: scheduledFor)
        context.insert(la)
        return la
    }

    /// Creates and inserts a presented LessonAssignment.
    @MainActor
    static func insertPresented(
        lessonID: UUID,
        studentIDs: [UUID],
        presentedAt: Date = Date(),
        context: ModelContext
    ) -> LessonAssignment {
        let la = makePresented(lessonID: lessonID, studentIDs: studentIDs, presentedAt: presentedAt)
        context.insert(la)
        return la
    }
}
