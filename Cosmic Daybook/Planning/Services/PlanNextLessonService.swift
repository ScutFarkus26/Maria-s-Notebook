//
//  PlanNextLessonService.swift
//  Cosmic Daybook
//
//  Unified service for planning the next lesson in a sequence/area sequence.
//  Every caller that plans or looks up the next lesson goes through here so
//  they all behave the same.
//

import Foundation
import CoreData

/// Service for finding and creating the next lesson in a area/sequence sequence.
/// Ensures consistent duplicate checking and creation logic across all entry points.
struct PlanNextLessonService {

    // MARK: - Result Type

    enum PlanResult {
        case success(CDLessonAssignment)
        case alreadyExists
        case noNextLesson
        case noStudents
    }

    // MARK: - Find Next CDLesson

    /// The next lesson in the same area and sequence, in the one lesson
    /// order every screen reads (`LessonOrder`): two lessons tied on
    /// `orderInSequence` used to come back in fetch order here while Groups
    /// read them by name (domain-logic review R21).
    /// - Parameters:
    ///   - current: The current lesson to find the successor for
    ///   - allLessons: All available lessons to search through
    /// - Returns: The next lesson in the sequence, or nil if none exists
    static func findNextLesson(after current: CDLesson, in allLessons: [CDLesson]) -> CDLesson? {
        LessonOrder.next(after: current, in: allLessons)
    }

    // MARK: - Check for Existing

    /// Checks if a CDLessonAssignment already exists for the given lesson and students.
    /// Uses consistent criteria: same lesson ID, same students, and not yet given (presentedAt == nil)
    /// AND not yet scheduled (scheduledFor == nil) - i.e., would be in the inbox.
    static func existsInInbox(
        lessonID: UUID,
        studentIDs: Set<UUID>,
        in existingLessonAssignments: [CDLessonAssignment]
    ) -> Bool {
        existingLessonAssignments.contains { la in
            la.lessonIDUUID == lessonID &&
            Set(la.resolvedStudentIDs) == studentIDs &&
            la.presentedAt == nil &&
            la.scheduledFor == nil
        }
    }

    // MARK: - Core Data Plan Next CDLesson

    /// Plans the next lesson when you already know what the next lesson is.
    /// Used when the caller has already determined the next lesson (e.g., from UI state).
    @discardableResult
    // swiftlint:disable:next function_parameter_count
    static func planLesson(
        _ nextLesson: CDLesson,
        forStudents studentIDs: Set<UUID>,
        allStudents: [CDStudent],
        allLessons: [CDLesson],
        existingLessonAssignments: [CDLessonAssignment],
        context: NSManagedObjectContext,
        autoPromoteFromYearPlan: Bool = true
    ) -> PlanResult {
        guard !studentIDs.isEmpty else {
            return .noStudents
        }

        guard let nextLessonID = nextLesson.id else { return .noNextLesson }

        // Check if it already exists
        if existsInInbox(lessonID: nextLessonID, studentIDs: studentIDs, in: existingLessonAssignments) {
            return .alreadyExists
        }

        // Create the new CDLessonAssignment (auto-inserted by Core Data init)
        let newAssignment = PresentationFactory.makeDraft(
            lessonID: nextLessonID,
            studentIDs: Array(studentIDs),
            context: context
        )

        // Auto-promote from Year Plan if a matching entry exists
        if autoPromoteFromYearPlan {
            YearPlanPromotionService.autoPromoteIfPlanExists(
                assignment: newAssignment, context: context
            )
        }

        return .success(newAssignment)
    }

}
