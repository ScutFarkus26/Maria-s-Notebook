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
        /// lessonID → the children with a mastery mark on it
        /// (`PresentationRecordIndex.masteryMarks`).
        let masteryMarks: [String: Set<String>]
        /// The children judged: enrolled and shown. Nil judges everyone on a plan.
        let judgedStudentIDs: Set<UUID>?

        init(
            lessons: [CDLesson],
            lessonAssignments: [CDLessonAssignment],
            workModels: [CDWorkModel],
            batch: [CDLessonAssignment],
            masteryMarks: [String: Set<String>]?,
            judgedStudentIDs: Set<UUID>?
        ) {
            // Build lesson lookup. Sync can hand back two rows with one id;
            // the first is kept rather than trapping.
            self.lessonsByID = Dictionary(
                lessons.compactMap { lesson in
                    guard let id = lesson.id else { return nil }
                    return (id, lesson)
                },
                uniquingKeysWith: { first, _ in first }
            )

            // Pre-compute preceding lessons for all lessons in one grouped pass.
            self.precedingLessonCache = BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)

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
            let context = lessons.first?.managedObjectContext
            self.managedObjectContext = context

            // A caller that read the marks already (to know when they change)
            // passes them; otherwise they are read here, for the batch's
            // preceding lessons only.
            if let masteryMarks {
                self.masteryMarks = masteryMarks
            } else if let context {
                let preceding = BlockingAlgorithmEngine.precedingLessonIDs(
                    for: batch, precedingLessons: precedingLessonCache
                )
                self.masteryMarks = PresentationRecordIndex.masteryMarks(lessonIDs: preceding, in: context)
            } else {
                self.masteryMarks = [:]
            }
            self.judgedStudentIDs = judgedStudentIDs
        }
    }

    // MARK: - Batch Blocking Check

    /// Efficiently check blocking status for multiple LessonAssignments at once.
    /// This method pre-computes lookup structures to avoid redundant work.
    ///
    /// - Parameters:
    ///   - lessonAssignments: Array of LessonAssignments to check
    ///   - lessons: All lessons (needed for sequence structure)
    ///   - allLessonAssignments: All LessonAssignments (for presented lookup)
    ///   - workModels: Open work, plus the closed work of the preceding
    ///     presentations (`precedingPresentationIDs`): a child whose only
    ///     practice is closed is ready, and without it she reads as having
    ///     none and, when the lesson needs practice, as not ready.
    ///   - masteryMarks: lessonID → children with a mastery mark on it, for
    ///     the preceding lessons (`PresentationRecordIndex.masteryMarks`); nil
    ///     reads them through the lessons' context.
    ///   - judgedStudentIDs: the children whose readiness counts (enrolled and
    ///     shown); a departed or hidden child on a plan neither holds it in
    ///     Brewing nor counts in "N of M ready". Nil judges everyone.
    /// - Returns: Dictionary mapping CDLessonAssignment ID to BlockingCheckResult
    static func checkBlocking(
        forBatch lessonAssignments: [CDLessonAssignment],
        lessons: [CDLesson],
        allLessonAssignments: [CDLessonAssignment] = [],
        workModels: [CDWorkModel],
        masteryMarks: [String: Set<String>]? = nil,
        judgedStudentIDs: Set<UUID>? = nil
    ) -> [UUID: BlockingCheckResult] {
        guard !lessonAssignments.isEmpty else { return [:] }

        // Build optimized lookup structures once
        let context = BlockingContext(
            lessons: lessons,
            lessonAssignments: allLessonAssignments.isEmpty ? lessonAssignments : allLessonAssignments,
            workModels: workModels,
            batch: lessonAssignments,
            masteryMarks: masteryMarks,
            judgedStudentIDs: judgedStudentIDs
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

        // Find presented assignments for the preceding lesson
        let precedingLessonIDStr = precedingLesson.id?.uuidString ?? ""
        let precedingAssignments = context.presentedAssignmentsByLessonID[precedingLessonIDStr] ?? []
        let marked = context.masteryMarks[precedingLessonIDStr] ?? []

        // Build per-student readiness. With neither gate required, every
        // child reads ready and nothing is open. Only the children shown are
        // judged (bug hunt 2026-11-03 #12).
        var perStudentReadiness: [UUID: StudentReadiness] = [:]
        var totalPrereqOpen = 0

        for studentID in la.resolvedStudentIDs where context.judgedStudentIDs?.contains(studentID) ?? true {
            let verdict = readiness(
                of: studentID,
                givings: givings(for: studentID, among: precedingAssignments),
                mastered: marked.contains(studentID.uuidString),
                rules: rules,
                workByPresentationID: context.workByPresentationID
            )
            totalPrereqOpen += verdict.openWorkCount
            perStudentReadiness[studentID] = verdict.readiness
        }

        let isBlocked = perStudentReadiness.values.contains { !$0.isReady }

        return BlockingCheckResult(
            isBlocked: isBlocked,
            prereqOpenCount: totalPrereqOpen,
            perStudentReadiness: perStudentReadiness
        )
    }

    // MARK: - One Child

    /// Every giving of a lesson (out of `presented`, any children's) that
    /// `studentID` was on, latest first: the latest one's work gates her, and
    /// a confirmation on any of them counts. Taking the first in fetch order
    /// ignored a confirmation made on the other giving.
    nonisolated static func givings(
        for studentID: UUID, among presented: [CDLessonAssignment]
    ) -> [CDLessonAssignment] {
        latestFirst(presented.filter { assignment in
            assignment.state == .presented && assignment.resolvedStudentIDs.contains(studentID)
        })
    }

    /// One child's readiness for the lesson after the one `givings` gave
    /// her: the rule `checkBlocking` applies to each child on a plan. The
    /// checklist asks it too (`ChecklistMatrixBuilder`), so its "Not yet"
    /// and Presentations' Ready can't disagree.
    ///
    /// - Parameters:
    ///   - givings: her givings of the preceding lesson, from
    ///     `givings(for:among:)`. Empty means it wasn't given to her.
    ///   - mastered: she has a mastery mark on the preceding lesson (any
    ///     marked history row, the Checklist's Mastered included). It counts
    ///     as the teacher's confirmation, as it does for the Checklist and
    ///     Today (`ReadyForNextEngine.readiness`), and with no giving on record
    ///     it stands in for the practice too (bug hunt 2026-11-03 #5).
    ///   - rules: the preceding lesson's progression rules.
    ///   - workByPresentationID: the work on those givings, open **and**
    ///     closed: with open work alone, a child whose practice is done reads
    ///     as having none and, when the lesson needs practice, as not ready.
    /// - Returns: her readiness, and how many of her rows are still open.
    static func readiness(
        of studentID: UUID,
        givings: [CDLessonAssignment],
        mastered: Bool,
        rules: LessonProgressionRules.ResolvedRules,
        workByPresentationID: [String: [CDWorkModel]]
    ) -> (readiness: StudentReadiness, openWorkCount: Int) {
        let latest = givings.first
        var openWorkCount = 0

        // Gate 1: Work completion
        var workComplete = true
        if rules.requiresPractice, let assignment = latest {
            let presentationID = assignment.id?.uuidString ?? ""
            // Only this student's own work can gate their readiness — a classmate's
            // unfinished work on the same group presentation must not block them.
            let prerequisiteWork = gatingWork(
                for: studentID, among: workByPresentationID[presentationID] ?? []
            )

            if prerequisiteWork.isEmpty {
                // No work assigned yet — if practice is required, student isn't ready
                workComplete = !assignment.needsPractice
            } else {
                for work in prerequisiteWork where !isWorkCompleteForStudent(work: work, studentID: studentID) {
                    workComplete = false
                    openWorkCount += 1
                }
            }
        } else if rules.requiresPractice && latest == nil {
            // Preceding lesson hasn't been presented to this student; a
            // mastery mark says she has it all the same.
            workComplete = mastered
        }

        // Gate 2: Teacher confirmation, or a mastery mark. Not given to her
        // and not marked means not confirmed.
        var teacherConfirmed = true
        if rules.requiresTeacherConfirmation {
            teacherConfirmed = mastered || givings.contains { $0.isStudentConfirmed(studentID) }
        }

        let readiness = StudentReadiness(
            studentID: studentID,
            isReady: workComplete && teacherConfirmed,
            workComplete: workComplete,
            teacherConfirmed: teacherConfirmed,
            workRequired: rules.requiresPractice,
            confirmationRequired: rules.requiresTeacherConfirmation
        )
        return (readiness, openWorkCount)
    }

    /// Presentations newest first: by the day given (an undated one counts
    /// as oldest), then by when the record was made, then by id so every
    /// device orders a tie the same way.
    nonisolated static func latestFirst(_ assignments: [CDLessonAssignment]) -> [CDLessonAssignment] {
        assignments.sorted { lhs, rhs in
            let lhsGiven = lhs.presentedAt ?? .distantPast
            let rhsGiven = rhs.presentedAt ?? .distantPast
            if lhsGiven != rhsGiven { return lhsGiven > rhsGiven }
            let lhsMade = lhs.createdAt ?? .distantPast
            let rhsMade = rhs.createdAt ?? .distantPast
            if lhsMade != rhsMade { return lhsMade > rhsMade }
            return (lhs.id?.uuidString ?? "") > (rhs.id?.uuidString ?? "")
        }
    }

    /// The ids of the given presentations whose work can gate `unscheduled`:
    /// every giving of each one's preceding lesson. The caller reads this
    /// work whatever its status, since a child whose practice is done is
    /// ready, and with only open work passed in she read as having none.
    nonisolated static func precedingPresentationIDs(
        for unscheduled: [CDLessonAssignment],
        lessons: [CDLesson],
        allLessonAssignments: [CDLessonAssignment]
    ) -> Set<String> {
        let preceding = buildPrecedingLessonCache(lessons)
        let precedingLessonIDs = Set(unscheduled.compactMap { la -> String? in
            guard let lessonID = UUID(uuidString: la.lessonID) else { return nil }
            return preceding[lessonID]?.id?.uuidString
        })
        guard !precedingLessonIDs.isEmpty else { return [] }
        return Set(allLessonAssignments.compactMap { assignment -> String? in
            guard assignment.state == .presented else { return nil }
            let lessonID = UUID(uuidString: assignment.lessonID)?.uuidString ?? assignment.lessonID
            guard precedingLessonIDs.contains(lessonID) else { return nil }
            return assignment.id?.uuidString
        })
    }

    /// The preceding lesson of each of `assignments`' lessons, as UUID
    /// strings: where a mastery mark readies a child for them.
    nonisolated static func precedingLessonIDs(
        for assignments: [CDLessonAssignment], precedingLessons: [UUID: CDLesson]
    ) -> Set<String> {
        Set(assignments.compactMap { la -> String? in
            guard let lessonID = UUID(uuidString: la.lessonID) else { return nil }
            return precedingLessons[lessonID]?.id?.uuidString
        })
    }

    // MARK: - Find Preceding CDLesson

    /// Find the preceding lesson in the sequence (same area/sequence, previous orderInSequence).
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
        let currentArea = currentLesson.area.trimmed()
        let currentSequence = currentLesson.sequence.trimmed()

        guard !currentArea.isEmpty, !currentSequence.isEmpty else {
            return nil
        }

        // Find all lessons in the same area/sequence
        let candidates = lessons.filter { lesson in
            lesson.area.trimmed().caseInsensitiveCompare(currentArea) == .orderedSame &&
            lesson.sequence.trimmed().caseInsensitiveCompare(currentSequence) == .orderedSame
        }
        .sorted { $0.orderInSequence < $1.orderInSequence }

        // Find the current lesson's index
        guard let currentIndex = candidates.firstIndex(where: { $0.id == currentLesson.id }),
              currentIndex > 0 else {
            return nil // No preceding lesson
        }

        return candidates[currentIndex - 1]
    }
}
