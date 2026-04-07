//
//  PlanNextLessonService.swift
//  Maria's Notebook
//
//  Unified service for planning the next lesson in a group/subject sequence.
//  Consolidates duplicate logic from PlanningWeekViewContent, PlanningActions,
//  and PresentationDetailActions to ensure consistent behavior.
//

import Foundation
import CoreData

/// Service for finding and creating the next lesson in a subject/group sequence.
/// Ensures consistent duplicate checking and creation logic across all entry points.
@MainActor
struct PlanNextLessonService {

    // MARK: - Result Type

    enum PlanResult {
        case success(CDLessonAssignment)
        case alreadyExists
        case noNextLesson
        case noCurrentLesson
        case currentNotMastered(reason: String)
        case emptySubjectOrGroup
        case noStudents
    }

    // MARK: - Find Next CDLesson

    /// Finds the next lesson in the same subject/group sequence.
    /// - Parameters:
    ///   - current: The current lesson to find the successor for
    ///   - allLessons: All available lessons to search through
    /// - Returns: The next lesson in the sequence, or nil if none exists
    static func findNextLesson(after current: CDLesson, in allLessons: [CDLesson]) -> CDLesson? {
        let currentSubject = current.subject.trimmed()
        let currentGroup = current.group.trimmed()

        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return nil }

        // Find all lessons in the same subject/group, sorted by order
        let candidates = allLessons
            .filter { lesson in
                lesson.subject.trimmed().caseInsensitiveCompare(currentSubject) == .orderedSame &&
                lesson.group.trimmed().caseInsensitiveCompare(currentGroup) == .orderedSame
            }
            .sorted { $0.orderInGroup < $1.orderInGroup }

        // Find the current lesson's position and return the next one
        guard let currentIndex = candidates.firstIndex(where: { $0.id == current.id }),
              currentIndex + 1 < candidates.count else {
            return nil
        }

        return candidates[currentIndex + 1]
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
            Set(la.studentUUIDs) == studentIDs &&
            la.presentedAt == nil &&
            la.scheduledFor == nil
        }
    }

    /// Checks if a CDLessonAssignment already exists that hasn't been given yet.
    /// This is a less strict check - the lesson may be scheduled but not yet presented.
    static func existsActive(
        lessonID: UUID,
        studentIDs: Set<UUID>,
        in existingLessonAssignments: [CDLessonAssignment]
    ) -> Bool {
        existingLessonAssignments.contains { la in
            la.lessonIDUUID == lessonID &&
            Set(la.studentUUIDs) == studentIDs &&
            la.presentedAt == nil
        }
    }

    // MARK: - Core Data Plan Next CDLesson

    /// Plans the next lesson in the sequence for the given CDLessonAssignment.
    /// This is the main entry point that should be used by all UI components.
    @discardableResult
    static func planNextLesson(
        for lessonAssignment: CDLessonAssignment,
        allLessons: [CDLesson],
        allStudents: [CDStudent],
        existingLessonAssignments: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) -> PlanResult {
        // Get the current lesson
        guard let lessonIDUUID = lessonAssignment.lessonIDUUID,
              let currentLesson = allLessons.first(where: { $0.id == lessonIDUUID }) else {
            return .noCurrentLesson
        }

        // Find the next lesson in the sequence
        guard let nextLesson = findNextLesson(after: currentLesson, in: allLessons) else {
            return .noNextLesson
        }

        // Get the student IDs
        let studentIDs = Set(lessonAssignment.studentUUIDs)
        guard !studentIDs.isEmpty else {
            return .noStudents
        }

        // Check mastery gates on the current lesson before advancing
        let rules = LessonProgressionRules.resolve(for: currentLesson, context: context)
        if rules.requiresPractice || rules.requiresTeacherConfirmation {
            if let reason = checkMasteryGates(
                assignment: lessonAssignment, rules: rules, context: context
            ) {
                return .currentNotMastered(reason: reason)
            }
        }

        guard let nextLessonID = nextLesson.id else { return .noNextLesson }

        // Check if it already exists (using strict inbox check)
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
        YearPlanPromotionService.autoPromoteIfPlanExists(
            assignment: newAssignment, context: context
        )

        return .success(newAssignment)
    }

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
        context: NSManagedObjectContext
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
        YearPlanPromotionService.autoPromoteIfPlanExists(
            assignment: newAssignment, context: context
        )

        return .success(newAssignment)
    }

    // MARK: - Mastery Gate Check

    /// Checks whether the current lesson's mastery gates are satisfied for the assignment's students.
    /// Returns a human-readable reason string if gates are NOT met, or nil if all clear.
    private static func checkMasteryGates(
        assignment: CDLessonAssignment,
        rules: LessonProgressionRules.ResolvedRules,
        context: NSManagedObjectContext
    ) -> String? {
        // Only check presented assignments — drafts/scheduled shouldn't block
        guard assignment.state == .presented else { return nil }

        var reasons: [String] = []

        // Gate 1: Practice/work completion
        if rules.requiresPractice {
            let workFetch = CDFetchRequest(CDWorkModel.self)
            workFetch.predicate = NSPredicate(
                format: "presentationID == %@",
                assignment.id?.uuidString ?? ""
            )
            let work = (try? context.fetch(workFetch)) ?? []

            if work.isEmpty && assignment.needsPractice {
                reasons.append("practice not yet assigned")
            } else if work.contains(where: { $0.status != .complete }) {
                reasons.append("practice not yet complete")
            }
        }

        // Gate 2: Teacher confirmation
        if rules.requiresTeacherConfirmation {
            let studentIDs = assignment.studentUUIDs
            let unconfirmed = studentIDs.filter { !assignment.isStudentConfirmed($0) }
            if !unconfirmed.isEmpty {
                reasons.append("teacher confirmation pending")
            }
        }

        return reasons.isEmpty ? nil : "Current lesson not yet mastered: " + reasons.joined(separator: ", ")
    }

    // Deprecated SwiftData bridge methods removed - no longer needed with Core Data.
}
