//
//  StudentLessonFactory.swift
//  Maria's Notebook
//
//  Centralizes StudentLesson creation to eliminate duplicated initialization logic.
//

import Foundation
import SwiftData

enum StudentLessonFactory {

    // MARK: - Unscheduled/Draft (Inbox)

    /// Creates an unscheduled StudentLesson (appears in inbox).
    /// Use when creating a new lesson that hasn't been scheduled yet.
    static func makeUnscheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> StudentLesson {
        StudentLesson(
            id: id,
            lessonID: lessonID,
            studentIDs: studentIDs,
            createdAt: createdAt,
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
    }

    /// Creates an unscheduled StudentLesson with relationship objects.
    static func makeUnscheduled(
        lesson: Lesson,
        students: [Student],
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> StudentLesson {
        let sl = StudentLesson(
            id: id,
            lesson: lesson,
            students: students,
            createdAt: createdAt,
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        return sl
    }

    // MARK: - Scheduled

    /// Creates a scheduled StudentLesson for a specific date/time.
    static func makeScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> StudentLesson {
        StudentLesson(
            id: id,
            lessonID: lessonID,
            studentIDs: studentIDs,
            createdAt: createdAt,
            scheduledFor: scheduledFor,
            givenAt: nil,
            isPresented: false,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
    }

    /// Creates a scheduled StudentLesson with relationship objects.
    static func makeScheduled(
        lesson: Lesson,
        students: [Student],
        scheduledFor: Date,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> StudentLesson {
        let sl = StudentLesson(
            id: id,
            lesson: lesson,
            students: students,
            createdAt: createdAt,
            scheduledFor: scheduledFor,
            givenAt: nil,
            isPresented: false,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        return sl
    }

    // MARK: - Presented/Given

    /// Creates a StudentLesson marked as presented/given.
    /// Use when marking a lesson as complete.
    static func makePresented(
        lessonID: UUID,
        studentIDs: [UUID],
        givenAt: Date = Date(),
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> StudentLesson {
        StudentLesson(
            id: id,
            lessonID: lessonID,
            studentIDs: studentIDs,
            createdAt: createdAt,
            scheduledFor: nil,
            givenAt: givenAt,
            isPresented: true,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
    }

    /// Creates a presented StudentLesson with relationship objects.
    static func makePresented(
        lesson: Lesson,
        students: [Student],
        givenAt: Date = Date(),
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> StudentLesson {
        let sl = StudentLesson(
            id: id,
            lesson: lesson,
            students: students,
            createdAt: createdAt,
            scheduledFor: nil,
            givenAt: givenAt,
            isPresented: true,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        return sl
    }

    // MARK: - From Backup/DTO

    /// Creates a StudentLesson from a backup DTO with all fields populated.
    static func makeFromBackup(
        id: UUID,
        lessonID: UUID,
        studentIDs: [UUID],
        createdAt: Date,
        scheduledFor: Date?,
        givenAt: Date?,
        isPresented: Bool,
        notes: String,
        needsPractice: Bool,
        needsAnotherPresentation: Bool,
        followUpWork: String
    ) -> StudentLesson {
        StudentLesson(
            id: id,
            lessonID: lessonID,
            studentIDs: studentIDs,
            createdAt: createdAt,
            scheduledFor: scheduledFor,
            givenAt: givenAt,
            isPresented: isPresented,
            notes: notes,
            needsPractice: needsPractice,
            needsAnotherPresentation: needsAnotherPresentation,
            followUpWork: followUpWork
        )
    }
}

// MARK: - Convenience Extensions

extension StudentLessonFactory {

    /// Attaches relationship objects to a StudentLesson and syncs denormalized fields.
    /// Call after creating with ID-based factory methods when you have the actual objects.
    static func attachRelationships(
        to studentLesson: StudentLesson,
        lesson: Lesson?,
        students: [Student]
    ) {
        studentLesson.lesson = lesson
        studentLesson.students = students
        studentLesson.syncSnapshotsFromRelationships()
    }

    /// Creates and inserts an unscheduled StudentLesson into the context.
    static func insertUnscheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        into context: ModelContext
    ) -> StudentLesson {
        let sl = makeUnscheduled(lessonID: lessonID, studentIDs: studentIDs)
        context.insert(sl)
        return sl
    }

    /// Creates and inserts a scheduled StudentLesson into the context.
    static func insertScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date,
        into context: ModelContext
    ) -> StudentLesson {
        let sl = makeScheduled(lessonID: lessonID, studentIDs: studentIDs, scheduledFor: scheduledFor)
        context.insert(sl)
        return sl
    }

    /// Creates and inserts a presented StudentLesson into the context.
    static func insertPresented(
        lessonID: UUID,
        studentIDs: [UUID],
        givenAt: Date = Date(),
        into context: ModelContext
    ) -> StudentLesson {
        let sl = makePresented(lessonID: lessonID, studentIDs: studentIDs, givenAt: givenAt)
        context.insert(sl)
        return sl
    }
}
