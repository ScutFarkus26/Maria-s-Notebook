//
//  ChecklistSyncHelper.swift
//  Maria's Notebook
//
//  Keeps LessonAssignment in sync when StudentLesson is created, updated, or deleted.
//  Temporary bridge used during the migration from StudentLesson to LessonAssignment.
//

import Foundation
import SwiftData
import OSLog

@MainActor
enum ChecklistSyncHelper {
    private static let logger = Logger.app(category: "ChecklistSync")

    // MARK: - Sync After Presented

    /// Call after a StudentLesson is created or updated as presented.
    static func syncAfterPresented(studentLesson sl: StudentLesson, context: ModelContext) {
        let slIDString = sl.id.uuidString

        if let la = findMatchingAssignment(slIDString: slIDString, context: context) {
            la.studentIDs = sl.studentIDs
            if la.state != .presented {
                la.stateRaw = LessonAssignmentState.presented.rawValue
                la.presentedAt = la.presentedAt ?? sl.givenAt ?? Date()
            }
            la.modifiedAt = Date()
        } else {
            guard let lessonUUID = UUID(uuidString: sl.lessonID) else { return }
            let studentUUIDs = sl.studentIDs.compactMap { UUID(uuidString: $0) }
            guard !studentUUIDs.isEmpty else { return }

            let la = PresentationFactory.makePresented(
                lessonID: lessonUUID,
                studentIDs: studentUUIDs,
                presentedAt: sl.givenAt ?? Date()
            )
            la.migratedFromStudentLessonID = slIDString
            la.lesson = sl.lesson
            if let lesson = sl.lesson {
                la.lessonTitleSnapshot = lesson.name
                la.lessonSubheadingSnapshot = lesson.subheading
            }
            context.insert(la)
            logger.debug("Created presented LessonAssignment for StudentLesson(\(sl.id))")
        }
    }

    // MARK: - Sync After Draft

    /// Call after a StudentLesson is created as unscheduled (inbox).
    static func syncAfterDraft(studentLesson sl: StudentLesson, context: ModelContext) {
        let slIDString = sl.id.uuidString

        if let la = findMatchingAssignment(slIDString: slIDString, context: context) {
            la.studentIDs = sl.studentIDs
            la.modifiedAt = Date()
        } else {
            guard let lessonUUID = UUID(uuidString: sl.lessonID) else { return }
            let studentUUIDs = sl.studentIDs.compactMap { UUID(uuidString: $0) }
            guard !studentUUIDs.isEmpty else { return }

            let la = PresentationFactory.makeDraft(
                lessonID: lessonUUID,
                studentIDs: studentUUIDs
            )
            la.migratedFromStudentLessonID = slIDString
            la.lesson = sl.lesson
            context.insert(la)
            logger.debug("Created draft LessonAssignment for StudentLesson(\(sl.id))")
        }
    }

    // MARK: - Sync After Student Added

    /// Call after a student is appended to an existing StudentLesson.
    static func syncAfterStudentAdded(studentLesson sl: StudentLesson, context: ModelContext) {
        let slIDString = sl.id.uuidString

        if let la = findMatchingAssignment(slIDString: slIDString, context: context) {
            la.studentIDs = sl.studentIDs
            la.modifiedAt = Date()
        }
        // If no matching LA exists, the full sync methods above will handle it
    }

    // MARK: - Sync After Student Removed

    /// Call after a student is removed from a StudentLesson (but the SL still has other students).
    static func syncAfterStudentRemoved(studentLesson sl: StudentLesson, context: ModelContext) {
        let slIDString = sl.id.uuidString

        if let la = findMatchingAssignment(slIDString: slIDString, context: context) {
            la.studentIDs = sl.studentIDs
            if la.studentIDs.isEmpty {
                context.delete(la)
                logger.debug("Deleted LessonAssignment (no students left) for StudentLesson(\(sl.id))")
            } else {
                la.modifiedAt = Date()
            }
        }
    }

    // MARK: - Sync After Deleted

    /// Call before a StudentLesson is deleted to also delete the matching LessonAssignment.
    static func syncAfterDeleted(studentLessonID: UUID, context: ModelContext) {
        let slIDString = studentLessonID.uuidString

        if let la = findMatchingAssignment(slIDString: slIDString, context: context) {
            context.delete(la)
            logger.debug("Deleted LessonAssignment for deleted StudentLesson(\(studentLessonID))")
        }
    }

    // MARK: - Private

    private static func findMatchingAssignment(slIDString: String, context: ModelContext) -> LessonAssignment? {
        context.safeFetch(
            FetchDescriptor<LessonAssignment>(
                predicate: #Predicate { $0.migratedFromStudentLessonID == slIDString }
            )
        ).first
    }
}
