import Foundation
import CoreData

// MARK: - Blocking Algorithm Engine

/// Engine for calculating prerequisite blocking logic for lessons.
/// Determines which lessons are blocked by incomplete work or missing teacher confirmation
/// from preceding lessons in a sequence, with per-student readiness tracking.
enum BlockingAlgorithmEngine {

    // MARK: - Types

    /// Result of checking if a CDLessonAssignment is blocked.
    struct BlockingCheckResult: Sendable {
        let isBlocked: Bool
        let prereqOpenCount: Int
        /// Per-student readiness breakdown. Empty when no preceding lesson exists.
        let perStudentReadiness: [UUID: StudentReadiness]

        /// Students who are ready to proceed.
        var readyStudentIDs: [UUID] {
            perStudentReadiness.filter(\.value.isReady).map(\.key)
        }

        /// Students who are not yet ready.
        var blockedStudentIDs: [UUID] {
            perStudentReadiness.filter { !$0.value.isReady }.map(\.key)
        }
    }

    /// Per-student readiness status for a specific lesson assignment.
    struct StudentReadiness: Sendable {
        let studentID: UUID
        let isReady: Bool
        /// Whether all required work is complete (gate 1).
        let workComplete: Bool
        /// Whether the teacher has confirmed proficiency (gate 2).
        let teacherConfirmed: Bool
        /// Whether practice/work is required by progression rules.
        let workRequired: Bool
        /// Whether teacher confirmation is required by progression rules.
        let confirmationRequired: Bool
    }

    /// Pre-computed lookup structures for efficient batch processing.
    private struct BlockingContext {
        let lessonsByID: [UUID: CDLesson]
        let precedingLessonCache: [UUID: CDLesson]
        /// Presented assignments keyed by lessonID (normalized UUID string).
        let presentedAssignmentsByLessonID: [String: [CDLessonAssignment]]
        let workByPresentationID: [String: [CDWorkModel]]
        let managedObjectContext: NSManagedObjectContext?

        init(lessons: [CDLesson], lessonAssignments: [CDLessonAssignment], workModels: [CDWorkModel]) {
            // Build lesson lookup
            self.lessonsByID = Dictionary(
                uniqueKeysWithValues: lessons.compactMap { lesson in
                    guard let id = lesson.id else { return nil }
                    return (id, lesson)
                }
            )

            // Pre-compute preceding lessons for all lessons
            var precedingCache: [UUID: CDLesson] = [:]
            for lesson in lessons {
                if let preceding = BlockingAlgorithmEngine.computePrecedingLesson(
                    currentLesson: lesson, lessons: lessons
                ) {
                    if let lessonID = lesson.id { precedingCache[lessonID] = preceding }
                }
            }
            self.precedingLessonCache = precedingCache

            // Group presented assignments by lessonID for flexible student matching
            var byLessonID: [String: [CDLessonAssignment]] = [:]
            for assignment in lessonAssignments where assignment.state == .presented {
                let normalizedLessonID = UUID(uuidString: assignment.lessonID)?.uuidString
                    ?? assignment.lessonID
                byLessonID[normalizedLessonID, default: []].append(assignment)
            }
            self.presentedAssignmentsByLessonID = byLessonID

            // Group work by presentation ID for O(1) lookup
            self.workByPresentationID = Dictionary(grouping: workModels, by: { $0.presentationID ?? "" })

            // Capture a context for progression rule lookups
            self.managedObjectContext = lessons.first?.managedObjectContext
        }
    }

    // MARK: - Batch Blocking Check

    /// Efficiently check blocking status for multiple LessonAssignments at once.
    /// This method pre-computes lookup structures to avoid redundant work.
    ///
    /// - Parameters:
    ///   - lessonAssignments: Array of LessonAssignments to check
    ///   - lessons: All lessons (needed for group structure)
    ///   - allLessonAssignments: All LessonAssignments (for presented lookup)
    ///   - workModels: All WorkModels (preferably filtered to non-complete)
    /// - Returns: Dictionary mapping CDLessonAssignment ID to BlockingCheckResult
    @MainActor
    static func checkBlocking(
        forBatch lessonAssignments: [CDLessonAssignment],
        lessons: [CDLesson],
        allLessonAssignments: [CDLessonAssignment] = [],
        workModels: [CDWorkModel]
    ) -> [UUID: BlockingCheckResult] {
        guard !lessonAssignments.isEmpty else { return [:] }

        // Build optimized lookup structures once
        let context = BlockingContext(
            lessons: lessons,
            lessonAssignments: allLessonAssignments.isEmpty ? lessonAssignments : allLessonAssignments,
            workModels: workModels
        )

        // Check each lesson assignment using pre-computed lookups
        var results: [UUID: BlockingCheckResult] = [:]
        for la in lessonAssignments {
            guard let laID = la.id else { continue }
            results[laID] = checkBlocking(for: la, context: context)
        }
        return results
    }

    /// Internal batch-optimized blocking check using pre-computed context.
    @MainActor
    private static func checkBlocking(for la: CDLessonAssignment, context: BlockingContext) -> BlockingCheckResult {
        // Check for manual unlock override
        if la.manuallyUnblocked {
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0, perStudentReadiness: [:])
        }

        // Find the current lesson using pre-computed lookup
        guard let currentLessonID = UUID(uuidString: la.lessonID),
              let currentLesson = context.lessonsByID[currentLessonID] else {
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0, perStudentReadiness: [:])
        }

        // Find the preceding lesson using pre-computed cache
        guard let currentLessonIDUnwrapped = currentLesson.id,
              let precedingLesson = context.precedingLessonCache[currentLessonIDUnwrapped] else {
            // No preceding lesson means no prerequisites to check
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0, perStudentReadiness: [:])
        }

        // Resolve progression rules for the preceding lesson
        let rules: LessonProgressionRules.ResolvedRules
        if let ctx = context.managedObjectContext {
            rules = LessonProgressionRules.resolve(for: precedingLesson, context: ctx)
        } else {
            // Fallback: both gates on
            rules = LessonProgressionRules.ResolvedRules(
                requiresPractice: true,
                requiresTeacherConfirmation: true,
                source: .builtInDefault
            )
        }

        // If neither gate is required, not blocked
        if !rules.requiresPractice && !rules.requiresTeacherConfirmation {
            let allReady = Dictionary(
                uniqueKeysWithValues: la.resolvedStudentIDs.map { sid in
                    (sid, StudentReadiness(
                        studentID: sid,
                        isReady: true,
                        workComplete: true,
                        teacherConfirmed: true,
                        workRequired: false,
                        confirmationRequired: false
                    ))
                }
            )
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0, perStudentReadiness: allReady)
        }

        // Find presented assignments for the preceding lesson
        let precedingLessonIDStr = precedingLesson.id?.uuidString ?? ""
        let precedingAssignments = context.presentedAssignmentsByLessonID[precedingLessonIDStr] ?? []

        // Build per-student readiness
        var perStudentReadiness: [UUID: StudentReadiness] = [:]
        var totalPrereqOpen = 0

        for studentID in la.resolvedStudentIDs {
            // Find the presented assignment that includes this student
            let studentAssignment = precedingAssignments.first { assignment in
                assignment.resolvedStudentIDs.contains(studentID)
            }

            // Gate 1: Work completion
            var workComplete = true
            if rules.requiresPractice, let assignment = studentAssignment {
                let presentationID = assignment.id?.uuidString ?? ""
                let prerequisiteWork = context.workByPresentationID[presentationID] ?? []

                if prerequisiteWork.isEmpty {
                    // No work assigned yet — if practice is required, student isn't ready
                    workComplete = !assignment.needsPractice
                } else {
                    for work in prerequisiteWork {
                        if !isWorkCompleteForStudent(work: work, studentID: studentID) {
                            workComplete = false
                            totalPrereqOpen += 1
                        }
                    }
                }
            } else if rules.requiresPractice && studentAssignment == nil {
                // Preceding lesson hasn't been presented to this student
                workComplete = false
            }

            // Gate 2: Teacher confirmation
            var teacherConfirmed = true
            if rules.requiresTeacherConfirmation {
                if let assignment = studentAssignment {
                    teacherConfirmed = assignment.isStudentConfirmed(studentID)
                } else {
                    // Preceding lesson hasn't been presented
                    teacherConfirmed = false
                }
            }

            let isReady = workComplete && teacherConfirmed

            perStudentReadiness[studentID] = StudentReadiness(
                studentID: studentID,
                isReady: isReady,
                workComplete: workComplete,
                teacherConfirmed: teacherConfirmed,
                workRequired: rules.requiresPractice,
                confirmationRequired: rules.requiresTeacherConfirmation
            )
        }

        let isBlocked = perStudentReadiness.values.contains { !$0.isReady }

        return BlockingCheckResult(
            isBlocked: isBlocked,
            prereqOpenCount: totalPrereqOpen,
            perStudentReadiness: perStudentReadiness
        )
    }

    // MARK: - Single Item Blocking Check (Convenience)

    /// Check if a CDLessonAssignment is blocked by incomplete prerequisite work from the preceding lesson.
    ///
    /// Note: For checking multiple LessonAssignments, use `checkBlocking(forBatch:)` instead for better performance.
    ///
    /// - Parameters:
    ///   - la: The CDLessonAssignment to check
    ///   - lessons: All lessons (needed for group structure)
    ///   - allLessonAssignments: All LessonAssignments (for presented lookup)
    ///   - workModels: All WorkModels (preferably filtered to non-complete)
    /// - Returns: A BlockingCheckResult indicating if blocked and how many prerequisites are open
    @MainActor
    static func checkBlocking(
        for la: CDLessonAssignment,
        lessons: [CDLesson],
        allLessonAssignments: [CDLessonAssignment] = [],
        workModels: [CDWorkModel]
    ) -> BlockingCheckResult {
        let context = BlockingContext(
            lessons: lessons,
            lessonAssignments: allLessonAssignments.isEmpty ? [la] : allLessonAssignments,
            workModels: workModels
        )
        return checkBlocking(for: la, context: context)
    }

    // MARK: - Find Preceding CDLesson

    /// Find the preceding lesson in the sequence (same subject/group, previous orderInGroup).
    /// This is the public API for external callers.
    ///
    /// - Parameters:
    ///   - currentLesson: The lesson to find the predecessor for
    ///   - lessons: All lessons
    /// - Returns: The preceding lesson, or nil if none exists
    static func findPrecedingLesson(currentLesson: CDLesson, lessons: [CDLesson]) -> CDLesson? {
        return computePrecedingLesson(currentLesson: currentLesson, lessons: lessons)
    }

    /// Internal implementation of preceding lesson computation.
    /// Separated to allow reuse in context initialization without recursion.
    private static func computePrecedingLesson(currentLesson: CDLesson, lessons: [CDLesson]) -> CDLesson? {
        let currentSubject = currentLesson.subject.trimmed()
        let currentGroup = currentLesson.group.trimmed()

        guard !currentSubject.isEmpty, !currentGroup.isEmpty else {
            return nil
        }

        // Find all lessons in the same subject/group
        let candidates = lessons.filter { lesson in
            lesson.subject.trimmed().caseInsensitiveCompare(currentSubject) == .orderedSame &&
            lesson.group.trimmed().caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }

        // Find the current lesson's index
        guard let currentIndex = candidates.firstIndex(where: { $0.id == currentLesson.id }),
              currentIndex > 0 else {
            return nil // No preceding lesson
        }

        return candidates[currentIndex - 1]
    }

    // MARK: - Work Completion Checks

    /// Check if work is complete (either statusRaw == "complete" OR all relevant participants have completedAt).
    ///
    /// - Parameters:
    ///   - work: The CDWorkModel to check
    ///   - requiredStudentIDs: The student IDs that need to have completed the work
    /// - Returns: True if work is complete for all required students
    static func isWorkComplete(work: CDWorkModel, requiredStudentIDs: [UUID]) -> Bool {
        if work.statusRaw == "complete" {
            return true
        }

        let participantsArray = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        guard !participantsArray.isEmpty else {
            return false
        }

        let requiredStudentIDStrings = Set(requiredStudentIDs.map(\.uuidString))
        let relevantParticipants = participantsArray.filter { requiredStudentIDStrings.contains($0.studentID) }

        return !relevantParticipants.isEmpty && relevantParticipants.allSatisfy { $0.completedAt != nil }
    }

    /// Check if work is complete for a single student.
    private static func isWorkCompleteForStudent(work: CDWorkModel, studentID: UUID) -> Bool {
        if work.statusRaw == "complete" {
            return true
        }

        let participantsArray = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        guard !participantsArray.isEmpty else {
            return false
        }

        let studentIDStr = studentID.uuidString
        guard let participant = participantsArray.first(where: { $0.studentID == studentIDStr }) else {
            return false
        }

        return participant.completedAt != nil
    }
}
