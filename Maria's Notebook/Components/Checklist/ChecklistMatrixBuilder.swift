import Foundation
import CoreData

// MARK: - Checklist Matrix Builder

/// Builds the matrix of student/lesson states for the checklist grid.
/// Computes status for each cell based on LessonAssignments and WorkModels.
enum ChecklistMatrixBuilder {

    // MARK: - Build Matrix

    /// Builds the matrix of states for all students and lessons.
    ///
    /// - Parameters:
    ///   - students: Students to include in the matrix
    ///   - lessons: Lessons to include in the matrix
    ///   - context: Model context for fetching data
    /// - Returns: Dictionary mapping student ID -> lesson ID -> state
    @MainActor
    static func buildMatrix(
        students: [CDStudent],
        lessons: [CDLesson],
        context: NSManagedObjectContext
    ) -> [UUID: [UUID: StudentChecklistRowState]] {
        let lessonIDStrings = Set(lessons.compactMap { $0.id?.uuidString })
        guard !lessonIDStrings.isEmpty else { return [:] }

        // Fetch LessonAssignments scoped to current lessons.
        // CDLessonAssignment has an #Index on lessonID, so per-lesson predicates are fast.
        // We batch fetches by lesson to leverage the index rather than fetching all records.
        var lasByLessonID: [String: [CDLessonAssignment]] = [:]
        for lessonIDString in lessonIDStrings {
            let descriptor: NSFetchRequest<CDLessonAssignment> = CDFetchRequest(CDLessonAssignment.self)
            descriptor.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
            lasByLessonID[lessonIDString] = context.safeFetch(descriptor)
        }

        // Fetch WorkModels scoped to current lessons using studentID index.
        // Build a lookup by lessonID for O(1) access per cell.
        var worksByLessonID: [String: [CDWorkModel]] = [:]
        for lessonIDString in lessonIDStrings {
            let descriptor: NSFetchRequest<CDWorkModel> = CDFetchRequest(CDWorkModel.self)
            descriptor.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
            worksByLessonID[lessonIDString] = context.safeFetch(descriptor)
        }

        var newMatrix: [UUID: [UUID: StudentChecklistRowState]] = [:]

        // Pre-compute staleness threshold date once instead of per-cell
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Pre-compute preceding lessons and progression rules for blocking reasons
        var precedingLessonMap: [UUID: CDLesson] = [:]
        var progressionRulesMap: [UUID: LessonProgressionRules.ResolvedRules] = [:]
        for lesson in lessons {
            guard let lessonID = lesson.id else { continue }
            if let preceding = BlockingAlgorithmEngine.findPrecedingLesson(currentLesson: lesson, lessons: lessons) {
                precedingLessonMap[lessonID] = preceding
                progressionRulesMap[lessonID] = LessonProgressionRules.resolve(for: preceding, context: context)
            }
        }

        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            let studentKey = student.cloudKitKey
            let studentUUID = student.id ?? UUID()

            for lesson in lessons {
                guard let lessonID = lesson.id else { continue }
                let lessonIDString = lessonID.uuidString
                let lasForLesson = lasByLessonID[lessonIDString] ?? []
                let studentLAs = lasForLesson.filter { $0.studentIDs.contains(studentKey) }
                let worksForLesson = worksByLessonID[lessonIDString] ?? []
                let studentWorks = worksForLesson.filter { work in
                    ((work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []).contains { $0.studentID == studentKey }
                }

                // Compute blocking reason for empty/scheduled cells
                let blockingReason: BlockingReason
                let isPresented = studentLAs.contains { $0.isPresented }
                if !isPresented, let precedingLesson = precedingLessonMap[lessonID] {
                    blockingReason = computeBlockingReason(
                        precedingLesson: precedingLesson,
                        rules: progressionRulesMap[lessonID],
                        studentID: studentUUID,
                        studentKey: studentKey,
                        lasByLessonID: lasByLessonID,
                        worksByLessonID: worksByLessonID
                    )
                } else {
                    blockingReason = .none
                }

                let state = buildCellState(
                    lesson: lesson,
                    studentLAs: studentLAs,
                    studentWorkModels: studentWorks,
                    calendar: calendar,
                    today: today,
                    blockingReason: blockingReason
                )
                studentRow[lessonID] = state
            }
            guard let studentID = student.id else { continue }
            newMatrix[studentID] = studentRow
        }

        return newMatrix
    }

    // MARK: - Private Helpers

    /// Staleness threshold: 14 weekdays (approx 2.8 calendar weeks)
    private static let staleWeekdays = 14

    /// Computes why a student is blocked from a lesson based on the preceding lesson's state.
    @MainActor
    private static func computeBlockingReason(
        precedingLesson: CDLesson,
        rules: LessonProgressionRules.ResolvedRules?,
        studentID: UUID,
        studentKey: String,
        lasByLessonID: [String: [CDLessonAssignment]],
        worksByLessonID: [String: [CDWorkModel]]
    ) -> BlockingReason {
        guard let rules, (rules.requiresPractice || rules.requiresTeacherConfirmation) else {
            return .none
        }

        let precedingIDStr = precedingLesson.id?.uuidString ?? ""
        let precedingLAs = lasByLessonID[precedingIDStr] ?? []
        let presentedLA = precedingLAs.first { $0.isPresented && $0.studentIDs.contains(studentKey) }

        guard let presentedLA else {
            // Preceding lesson hasn't been presented to this student
            return .prerequisiteNotPresented
        }

        var needsPractice = false
        var needsConfirmation = false

        if rules.requiresPractice {
            let precedingWorks = worksByLessonID[precedingIDStr] ?? []
            let studentWorks = precedingWorks.filter { work in
                ((work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []).contains { $0.studentID == studentKey }
            }
            let allComplete = !studentWorks.isEmpty && studentWorks.allSatisfy { $0.status == WorkStatus.complete }
            if studentWorks.isEmpty || !allComplete {
                needsPractice = true
            }
        }

        if rules.requiresTeacherConfirmation {
            if !presentedLA.isStudentConfirmed(studentID) {
                needsConfirmation = true
            }
        }

        if needsPractice && needsConfirmation {
            return .practiceAndConfirmation
        } else if needsPractice {
            return .practiceRequired
        } else if needsConfirmation {
            return .confirmationRequired
        }
        return .none
    }

    private static func buildCellState(
        lesson: CDLesson,
        studentLAs: [CDLessonAssignment],
        studentWorkModels: [CDWorkModel],
        calendar: Calendar,
        today: Date,
        blockingReason: BlockingReason = .none
    ) -> StudentChecklistRowState {
        let nonPresented = studentLAs.filter { !$0.isPresented }
        let plannedCandidate = nonPresented.first
        let isScheduled = !nonPresented.isEmpty
        let isInboxPlan = isScheduled && (plannedCandidate?.scheduledFor == nil)
        let isPresented = studentLAs.contains { $0.isPresented }

        let workModelForLesson = studentWorkModels.first
        let isActive = workModelForLesson?.isOpen ?? false
        let isComplete = workModelForLesson?.status == WorkStatus.complete
        let isWorkActive = studentWorkModels.contains { $0.status == WorkStatus.active }
        let isWorkReview = studentWorkModels.contains { $0.status == WorkStatus.review }

        // Compute staleness using pre-computed calendar & today (avoids per-cell allocation)
        let lastActivityDate = workModelForLesson?.lastTouchedAt ?? workModelForLesson?.createdAt
        let isStale: Bool = {
            guard !isComplete, let activity = lastActivityDate else { return false }
            let activityDay = calendar.startOfDay(for: activity)
            let totalDays = calendar.dateComponents([.day], from: activityDay, to: today).day ?? 0
            guard totalDays > 0 else { return false }
            let fullWeeks = totalDays / 7
            let remainingDays = totalDays % 7
            var weekdays = fullWeeks * 5
            let startWeekday = calendar.component(.weekday, from: activityDay)
            for i in 0..<remainingDays {
                let dayOfWeek = (startWeekday - 1 + i) % 7 + 1
                if dayOfWeek != 1 && dayOfWeek != 7 { weekdays += 1 }
            }
            return weekdays >= staleWeekdays
        }()

        return StudentChecklistRowState(
            lessonID: lesson.id ?? UUID(),
            plannedItemID: plannedCandidate?.id,
            presentationLogID: nil,
            contractID: workModelForLesson?.id,
            isScheduled: isScheduled,
            isPresented: isPresented,
            isActive: isActive,
            isComplete: isComplete,
            isWorkActive: isWorkActive,
            isWorkReview: isWorkReview,
            lastActivityDate: lastActivityDate,
            isStale: isStale,
            isInboxPlan: isInboxPlan,
            blockingReason: blockingReason
        )
    }
}
