import Foundation

// MARK: - Blocking Algorithm Engine

/// Engine for calculating prerequisite blocking logic for lessons.
/// Determines which lessons are blocked by incomplete work from preceding lessons in a sequence.
enum BlockingAlgorithmEngine {

    // MARK: - Types

    /// Result of checking if a CDLessonAssignment is blocked.
    struct BlockingCheckResult: Sendable {
        let isBlocked: Bool
        let prereqOpenCount: Int
    }
    
    /// Pre-computed lookup structures for efficient batch processing.
    private struct BlockingContext {
        let lessonsByID: [UUID: CDLesson]
        let precedingLessonCache: [UUID: CDLesson]
        let lessonAssignmentsByKey: [String: CDLessonAssignment]
        let workByPresentationID: [String: [CDWorkModel]]
        
        init(lessons: [CDLesson], lessonAssignments: [CDLessonAssignment], workModels: [CDWorkModel]) {
            // Build lesson lookup
            self.lessonsByID = Dictionary(uniqueKeysWithValues: lessons.compactMap { guard let id = $0.id else { return nil }; return (id, $0) })
            
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
            
            // Build lesson assignment lookup by composite key (lessonID + sorted student IDs)
            // Normalize through UUID to ensure consistent casing (e.g. CloudKit sync)
            var assignmentLookup: [String: CDLessonAssignment] = [:]
            for assignment in lessonAssignments where assignment.state == .presented {
                let normalizedIDs = assignment.studentIDs
                    .compactMap { UUID(uuidString: $0) }
                    .map(\.uuidString)
                    .sorted()
                    .joined(separator: ",")
                let normalizedLessonID = UUID(uuidString: assignment.lessonID)?.uuidString
                    ?? assignment.lessonID
                let key = "\(normalizedLessonID)|\(normalizedIDs)"
                assignmentLookup[key] = assignment
            }
            self.lessonAssignmentsByKey = assignmentLookup
            
            // Group work by presentation ID for O(1) lookup
            self.workByPresentationID = Dictionary(grouping: workModels, by: { $0.presentationID ?? "" })
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
    private static func checkBlocking(for la: CDLessonAssignment, context: BlockingContext) -> BlockingCheckResult {
        // Check for manual unlock override
        if la.manuallyUnblocked {
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
        }

        // Find the current lesson using pre-computed lookup
        guard let currentLessonID = UUID(uuidString: la.lessonID),
              let currentLesson = context.lessonsByID[currentLessonID] else {
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
        }

        // Find the preceding lesson using pre-computed cache
        guard let currentLessonIDUnwrapped = currentLesson.id,
              let precedingLesson = context.precedingLessonCache[currentLessonIDUnwrapped] else {
            // No preceding lesson means no prerequisites to check
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
        }

        // Build lookup key for lesson assignment
        let sortedStudentIDs = la.resolvedStudentIDs.map(\.uuidString).sorted().joined(separator: ",")
        let precedingLessonIDStr = precedingLesson.id?.uuidString ?? ""
        let assignmentKey = "\(precedingLessonIDStr)|\(sortedStudentIDs)"

        // Find the CDLessonAssignment using pre-computed lookup
        guard let precedingLessonAssignment = context.lessonAssignmentsByKey[assignmentKey] else {
            // No presentation for preceding lesson means no prerequisites
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
        }

        let presentationID = precedingLessonAssignment.id?.uuidString ?? ""

        // Find CDWorkModel records using pre-computed grouping
        guard let prerequisiteWork = context.workByPresentationID[presentationID] else {
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
        }

        // Check if ANY prerequisite work is incomplete for any required student
        var prereqOpenCount = 0
        var isBlocked = false

        for work in prerequisiteWork {
            let workIsComplete = isWorkComplete(work: work, requiredStudentIDs: la.resolvedStudentIDs)

            if !workIsComplete {
                prereqOpenCount += 1
                isBlocked = true
            }
        }

        return BlockingCheckResult(isBlocked: isBlocked, prereqOpenCount: prereqOpenCount)
    }

    // MARK: - Single Item Blocking Check (Convenience)

    /// Check if a CDLessonAssignment is blocked by incomplete prerequisite work from the preceding lesson.
    ///
    /// CDNote: For checking multiple LessonAssignments, use `checkBlocking(forBatch:)` instead for better performance.
    ///
    /// - Parameters:
    ///   - la: The CDLessonAssignment to check
    ///   - lessons: All lessons (needed for group structure)
    ///   - allLessonAssignments: All LessonAssignments (for presented lookup)
    ///   - workModels: All WorkModels (preferably filtered to non-complete)
    /// - Returns: A BlockingCheckResult indicating if blocked and how many prerequisites are open
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

}
