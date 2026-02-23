//
//  DualWriteCoordinator.swift
//  Maria's Notebook
//
//  Coordinates dual-write pattern during migration from StudentLesson to LessonAssignment.
//  Ensures both models stay in sync during the transition period.
//

import Foundation
import SwiftData
import OSLog

/// Errors that can occur during dual-write operations
enum DualWriteError: Error {
    case notFound
    case inconsistentState(String)
    case migrationLinkMissing
}

@MainActor
final class DualWriteCoordinator {
    private let context: ModelContext
    private let logger = Logger.app(category: "DualWrite")

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Create Operations

    /// Creates both a StudentLesson and matching LessonAssignment in draft state
    @discardableResult
    func createDraft(lessonID: UUID, studentIDs: [UUID]) throws -> (StudentLesson, LessonAssignment) {
        // Create StudentLesson
        let sl = StudentLessonFactory.makeUnscheduled(lessonID: lessonID, studentIDs: studentIDs)
        context.insert(sl)

        // Create matching LessonAssignment
        let la = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: studentIDs)
        la.migratedFromStudentLessonID = sl.id.uuidString
        context.insert(la)

        context.safeSave()
        logger.debug("Created draft: StudentLesson(\(sl.id)) ↔ LessonAssignment(\(la.id))")

        return (sl, la)
    }

    /// Creates both a StudentLesson and matching LessonAssignment with relationships
    @discardableResult
    func createDraft(lesson: Lesson, students: [Student]) throws -> (StudentLesson, LessonAssignment) {
        // Create StudentLesson
        let sl = StudentLessonFactory.makeUnscheduled(lesson: lesson, students: students)
        context.insert(sl)

        // Create matching LessonAssignment
        let la = PresentationFactory.makeDraft(lesson: lesson, students: students)
        la.migratedFromStudentLessonID = sl.id.uuidString
        context.insert(la)

        context.safeSave()
        logger.debug("Created draft with relationships: StudentLesson(\(sl.id)) ↔ LessonAssignment(\(la.id))")

        return (sl, la)
    }

    /// Creates both a StudentLesson and matching LessonAssignment in scheduled state
    @discardableResult
    func createScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date
    ) throws -> (StudentLesson, LessonAssignment) {
        // Create StudentLesson
        let sl = StudentLessonFactory.makeScheduled(
            lessonID: lessonID,
            studentIDs: studentIDs,
            scheduledFor: scheduledFor
        )
        context.insert(sl)

        // Create matching LessonAssignment
        let la = PresentationFactory.makeScheduled(
            lessonID: lessonID,
            studentIDs: studentIDs,
            scheduledFor: scheduledFor
        )
        la.migratedFromStudentLessonID = sl.id.uuidString
        context.insert(la)

        context.safeSave()
        logger.debug("Created scheduled: StudentLesson(\(sl.id)) ↔ LessonAssignment(\(la.id)) for \(scheduledFor)")

        return (sl, la)
    }

    // MARK: - Update Operations

    /// Schedules both a StudentLesson and its matching LessonAssignment
    func schedule(studentLessonID: UUID, for date: Date) throws {
        // Find StudentLesson
        guard let sl = try context.fetch(FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.id == studentLessonID }
        )).first else {
            throw DualWriteError.notFound
        }

        // Update StudentLesson
        sl.setScheduledFor(date, using: AppCalendar.shared)

        // Find and update matching LessonAssignment
        if let la = try findMatchingAssignment(for: sl) {
            la.schedule(for: date, using: AppCalendar.shared)
            logger.debug("Scheduled: StudentLesson(\(sl.id)) ↔ LessonAssignment(\(la.id)) for \(date)")
        } else {
            logger.warning("No matching LessonAssignment found for StudentLesson(\(sl.id))")
        }

        context.safeSave()
    }

    /// Unschedules both a StudentLesson and its matching LessonAssignment
    func unschedule(studentLessonID: UUID) throws {
        // Find StudentLesson
        guard let sl = try context.fetch(FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.id == studentLessonID }
        )).first else {
            throw DualWriteError.notFound
        }

        // Update StudentLesson
        sl.setScheduledFor(nil, using: AppCalendar.shared)

        // Find and update matching LessonAssignment
        if let la = try findMatchingAssignment(for: sl) {
            la.unschedule()
            logger.debug("Unscheduled: StudentLesson(\(sl.id)) ↔ LessonAssignment(\(la.id))")
        } else {
            logger.warning("No matching LessonAssignment found for StudentLesson(\(sl.id))")
        }

        context.safeSave()
    }

    /// Marks both a StudentLesson and its matching LessonAssignment as presented
    /// This delegates to the existing LifecycleService.recordPresentationAndExplodeWork
    /// which already creates/updates LessonAssignment
    func markPresented(studentLessonID: UUID, at date: Date) throws {
        // Find StudentLesson
        guard let sl = try context.fetch(FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.id == studentLessonID }
        )).first else {
            throw DualWriteError.notFound
        }

        // Update StudentLesson
        sl.isPresented = true
        sl.givenAt = date

        // LifecycleService.recordPresentationAndExplodeWork handles LessonAssignment creation
        // This is already implemented and working
        let _ = try LifecycleService.recordPresentationAndExplodeWork(
            from: sl,
            presentedAt: date,
            modelContext: context
        )

        context.safeSave()
        logger.debug("Marked presented: StudentLesson(\(sl.id)) via LifecycleService")
    }

    /// Updates notes on both StudentLesson and matching LessonAssignment
    func updateNotes(studentLessonID: UUID, notes: String) throws {
        // Find StudentLesson
        guard let sl = try context.fetch(FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.id == studentLessonID }
        )).first else {
            throw DualWriteError.notFound
        }

        // Update StudentLesson (unified notes)
        _ = sl.setLegacyNoteText(notes, in: context)

        // Find and update matching LessonAssignment (legacy string field still used)
        if let la = try findMatchingAssignment(for: sl) {
            la.notes = notes
            la.modifiedAt = Date()
            logger.debug("Updated notes: StudentLesson(\(sl.id)) ↔ LessonAssignment(\(la.id))")
        } else {
            logger.warning("No matching LessonAssignment found for StudentLesson(\(sl.id))")
        }

        context.safeSave()
    }

    /// Updates follow-up flags on both StudentLesson and matching LessonAssignment
    func updateFollowUp(
        studentLessonID: UUID,
        needsPractice: Bool? = nil,
        needsAnotherPresentation: Bool? = nil,
        followUpWork: String? = nil
    ) throws {
        // Find StudentLesson
        guard let sl = try context.fetch(FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.id == studentLessonID }
        )).first else {
            throw DualWriteError.notFound
        }

        // Update StudentLesson
        if let needsPractice = needsPractice {
            sl.needsPractice = needsPractice
        }
        if let needsAnotherPresentation = needsAnotherPresentation {
            sl.needsAnotherPresentation = needsAnotherPresentation
        }
        if let followUpWork = followUpWork {
            sl.followUpWork = followUpWork
        }

        // Find and update matching LessonAssignment
        if let la = try findMatchingAssignment(for: sl) {
            if let needsPractice = needsPractice {
                la.needsPractice = needsPractice
            }
            if let needsAnotherPresentation = needsAnotherPresentation {
                la.needsAnotherPresentation = needsAnotherPresentation
            }
            if let followUpWork = followUpWork {
                la.followUpWork = followUpWork
            }
            la.modifiedAt = Date()
            logger.debug("Updated follow-up: StudentLesson(\(sl.id)) ↔ LessonAssignment(\(la.id))")
        } else {
            logger.warning("No matching LessonAssignment found for StudentLesson(\(sl.id))")
        }

        context.safeSave()
    }

    // MARK: - Delete Operations

    /// Deletes both a StudentLesson and its matching LessonAssignment
    func delete(studentLessonID: UUID) throws {
        // Find StudentLesson
        guard let sl = try context.fetch(FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.id == studentLessonID }
        )).first else {
            throw DualWriteError.notFound
        }

        // Find and delete matching LessonAssignment
        if let la = try findMatchingAssignment(for: sl) {
            context.delete(la)
            logger.debug("Deleted: LessonAssignment(\(la.id))")
        } else {
            logger.warning("No matching LessonAssignment found for StudentLesson(\(sl.id))")
        }

        // Delete StudentLesson
        context.delete(sl)
        logger.debug("Deleted: StudentLesson(\(sl.id))")

        try context.save()
    }

    // MARK: - Helpers

    /// Finds the LessonAssignment that matches a given StudentLesson
    private func findMatchingAssignment(for sl: StudentLesson) throws -> LessonAssignment? {
        let slIDString = sl.id.uuidString
        return try context.fetch(FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.migratedFromStudentLessonID == slIDString }
        )).first
    }

    /// Validates that a StudentLesson has a matching LessonAssignment
    func validateSync(studentLessonID: UUID) throws -> Bool {
        guard let sl = try context.fetch(FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.id == studentLessonID }
        )).first else {
            return false
        }

        guard let la = try findMatchingAssignment(for: sl) else {
            return false
        }

        // Validate that key fields match
        let isValid =
            sl.lessonID == la.lessonID &&
            sl.studentIDs.sorted() == la.studentIDs.sorted() &&
            sl.isPresented == la.isPresented

        if !isValid {
            logger.error("Sync validation failed for StudentLesson(\(sl.id)) ↔ LessonAssignment(\(la.id))")
        }

        return isValid
    }
}
