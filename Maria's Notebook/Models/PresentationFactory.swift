//
//  PresentationFactory.swift
//  Maria's Notebook
//
//  Centralizes CDLessonAssignment creation to eliminate duplicated initialization logic.
//  Factory for creating LessonAssignment (Presentation) instances.
//

import Foundation
import CoreData
import SwiftData

enum PresentationFactory {

    // MARK: - Draft (Inbox)

    /// Creates a draft CDLessonAssignment (appears in inbox).
    @MainActor
    static func makeDraft(
        lessonID: UUID,
        studentIDs: [UUID],
        id: UUID = UUID(),
        createdAt: Date = Date(),
        context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let la = CDLessonAssignment(context: context)
        la.id = id
        la.createdAt = createdAt
        la.state = .draft
        la.lessonID = lessonID.uuidString
        la.studentIDs = studentIDs.map(\.uuidString)
        return la
    }

    /// Creates a draft CDLessonAssignment with relationship objects.
    @MainActor
    static func makeDraft(
        lesson: CDLesson,
        students: [CDStudent],
        id: UUID = UUID(),
        createdAt: Date = Date(),
        context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let la = CDLessonAssignment(context: context)
        la.id = id
        la.createdAt = createdAt
        la.state = .draft
        la.lesson = lesson
        la.lessonID = lesson.id?.uuidString ?? ""
        la.studentIDs = students.compactMap { $0.id?.uuidString }
        la.lessonTitleSnapshot = lesson.name
        la.lessonSubheadingSnapshot = lesson.subheading
        return la
    }

    // MARK: - Scheduled

    /// Creates a scheduled CDLessonAssignment for a specific date/time.
    @MainActor
    static func makeScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let la = makeDraft(lessonID: lessonID, studentIDs: studentIDs, id: id, createdAt: createdAt, context: context)
        la.schedule(for: scheduledFor)
        return la
    }

    /// Creates a scheduled CDLessonAssignment with relationship objects.
    @MainActor
    static func makeScheduled(
        lesson: CDLesson,
        students: [CDStudent],
        scheduledFor: Date,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let la = makeDraft(lesson: lesson, students: students, id: id, createdAt: createdAt, context: context)
        la.schedule(for: scheduledFor)
        return la
    }

    // MARK: - Presented/Given

    /// Creates a CDLessonAssignment marked as presented.
    @MainActor
    static func makePresented(
        lessonID: UUID,
        studentIDs: [UUID],
        presentedAt: Date = Date(),
        id: UUID = UUID(),
        createdAt: Date = Date(),
        context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let la = makeDraft(lessonID: lessonID, studentIDs: studentIDs, id: id, createdAt: createdAt, context: context)
        la.markPresented(at: presentedAt, snapshotLesson: false)
        return la
    }

    /// Creates a presented CDLessonAssignment with relationship objects.
    @MainActor
    static func makePresented(
        lesson: CDLesson,
        students: [CDStudent],
        presentedAt: Date = Date(),
        id: UUID = UUID(),
        createdAt: Date = Date(),
        context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let la = makeDraft(lesson: lesson, students: students, id: id, createdAt: createdAt, context: context)
        la.markPresented(at: presentedAt)
        return la
    }

    // MARK: - Previously Presented (Undated)

    /// Creates a CDLessonAssignment marked as previously presented (no date).
    @MainActor
    static func makePreviouslyPresented(
        lessonID: UUID,
        studentIDs: [UUID],
        id: UUID = UUID(),
        createdAt: Date = Date(),
        context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let la = makeDraft(lessonID: lessonID, studentIDs: studentIDs, id: id, createdAt: createdAt, context: context)
        la.state = .presented
        // No presentedAt date — this is an undated historical record
        return la
    }

    // MARK: - Legacy SwiftData overloads (transition period — remove when views migrate to Core Data)

    /// Legacy draft creation returning SwiftData LessonAssignment.
    @available(*, deprecated, message: "Migrate caller to Core Data CDLessonAssignment")
    @MainActor
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
            lessonID: lessonID,
            studentIDs: studentIDs
        )
    }

    /// Legacy insertDraft — creates and inserts into ModelContext.
    @available(*, deprecated, message: "Migrate caller to Core Data CDLessonAssignment")
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

    /// Legacy presented creation returning SwiftData LessonAssignment.
    @available(*, deprecated, message: "Migrate caller to Core Data CDLessonAssignment")
    @MainActor
    static func makePresented(
        lessonID: UUID,
        studentIDs: [UUID],
        presentedAt: Date = Date(),
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> LessonAssignment {
        let la = makeDraft(lessonID: lessonID, studentIDs: studentIDs, id: id, createdAt: createdAt)
        la.stateRaw = LessonAssignmentState.presented.rawValue
        la.presentedAt = presentedAt
        return la
    }

    /// Legacy relationship attachment for SwiftData LessonAssignment.
    @available(*, deprecated, message: "Migrate caller to Core Data CDLessonAssignment")
    @MainActor
    static func attachRelationships(
        to la: LessonAssignment,
        lesson: Lesson?,
        students: [Student]
    ) {
        la.lesson = lesson
        la.students = students
        la.syncSnapshotsFromRelationships()
    }

    /// Legacy insertPresented — creates, inserts, and marks as presented.
    @available(*, deprecated, message: "Migrate caller to Core Data CDLessonAssignment")
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

    /// Legacy insertPreviouslyPresented — creates, inserts, and marks as previously presented (undated).
    @available(*, deprecated, message: "Migrate caller to Core Data CDLessonAssignment")
    @MainActor
    @discardableResult
    static func insertPreviouslyPresented(
        lessonID: UUID,
        studentIDs: [UUID],
        context: ModelContext
    ) -> LessonAssignment {
        let la = makeDraft(lessonID: lessonID, studentIDs: studentIDs)
        la.stateRaw = LessonAssignmentState.presented.rawValue
        // No presentedAt date — this is an undated historical record
        context.insert(la)
        return la
    }

    /// Legacy scheduled creation returning SwiftData LessonAssignment.
    @available(*, deprecated, message: "Migrate caller to Core Data CDLessonAssignment")
    @MainActor
    static func makeScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> LessonAssignment {
        let la = makeDraft(lessonID: lessonID, studentIDs: studentIDs, id: id, createdAt: createdAt)
        la.scheduledFor = scheduledFor
        la.stateRaw = LessonAssignmentState.scheduled.rawValue
        return la
    }
}
