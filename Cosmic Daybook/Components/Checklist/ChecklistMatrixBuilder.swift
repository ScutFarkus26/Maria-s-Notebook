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
    static func buildMatrix(
        students: [CDStudent],
        lessons: [CDLesson],
        context: NSManagedObjectContext
    ) -> [UUID: [UUID: StudentChecklistRowState]] {
        let lessonIDArray = Array(Set(lessons.compactMap { $0.id?.uuidString }))
        guard !lessonIDArray.isEmpty else { return [:] }
        let lasByLessonID = assignmentsByLesson(lessonIDs: lessonIDArray, context: context)
        let worksByLessonID = worksByLesson(lessonIDs: lessonIDArray, context: context)

        var newMatrix: [UUID: [UUID: StudentChecklistRowState]] = [:]

        // Pre-compute staleness threshold date once instead of per-cell
        let calendar = AppCalendar.shared
        let today = calendar.startOfDay(for: Date())

        // Pre-compute preceding lessons and progression rules for blocking reasons
        let precedingLessonMap = BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)
        let progressionRulesMap = progressionRules(for: precedingLessonMap, context: context)

        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            let studentKey = student.cloudKitKey
            let studentUUID = student.id ?? UUID()

            for lesson in lessons {
                guard let lessonID = lesson.id else { continue }
                let lessonIDString = lessonID.uuidString
                let studentLAs = (lasByLessonID[lessonIDString] ?? [])
                    .filter { $0.studentKeys.contains(studentKey) }
                    .map(\.assignment)
                let studentWorks = (worksByLessonID[lessonIDString] ?? [])
                    .filter { $0.participantKeys.contains(studentKey) }
                    .map(\.work)

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

    // MARK: - Batched Reads

    /// One fetch for the whole area (it used to be one per lesson). Rows are
    /// grouped by lessonID in fetch order, so each lesson's list keeps the
    /// order its own `lessonID ==` fetch returned; each assignment's students
    /// are decoded once, not once per cell.
    private static func assignmentsByLesson(
        lessonIDs: [String],
        context: NSManagedObjectContext
    ) -> [String: [AssignmentEntry]] {
        let request: NSFetchRequest<CDLessonAssignment> = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID IN %@", lessonIDs)
        var result: [String: [AssignmentEntry]] = [:]
        for la in context.safeFetch(request) {
            result[la.lessonID, default: []].append(
                AssignmentEntry(assignment: la, studentKeys: Set(la.studentIDs))
            )
        }
        return result
    }

    /// Same for work, with participants prefetched so the per-cell participant
    /// check doesn't fault a to-many relationship per work per student.
    private static func worksByLesson(
        lessonIDs: [String],
        context: NSManagedObjectContext
    ) -> [String: [WorkEntry]] {
        let request: NSFetchRequest<CDWorkModel> = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID IN %@", lessonIDs)
        request.relationshipKeyPathsForPrefetching = ["participants"]
        var result: [String: [WorkEntry]] = [:]
        for work in context.safeFetch(request) {
            let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
            result[work.lessonID, default: []].append(
                WorkEntry(work: work, participantKeys: Set(participants.map(\.studentID)))
            )
        }
        return result
    }

    /// Rules for each lesson's predecessor. The sequence-settings lookup is
    /// shared by every predecessor filed under the same area + sequence, so it
    /// runs once per pair instead of once per lesson.
    private static func progressionRules(
        for precedingLessonMap: [UUID: CDLesson],
        context: NSManagedObjectContext
    ) -> [UUID: LessonProgressionRules.ResolvedRules] {
        var rules: [UUID: LessonProgressionRules.ResolvedRules] = [:]
        var settingsByGroup: [SettingsKey: CDLessonSequenceSettings?] = [:]
        for (lessonID, preceding) in precedingLessonMap {
            rules[lessonID] = LessonProgressionRules.resolve(for: preceding) {
                let key = SettingsKey(area: preceding.area, sequence: preceding.sequence)
                if let cached = settingsByGroup[key] { return cached }
                let found = CDLessonSequenceSettings.find(
                    area: preceding.area, sequence: preceding.sequence, context: context
                )
                settingsByGroup[key] = .some(found)
                return found
            }
        }
        return rules
    }

    // MARK: - Private Helpers

    /// An assignment with its decoded student keys.
    private struct AssignmentEntry {
        let assignment: CDLessonAssignment
        let studentKeys: Set<String>
    }

    /// A work item with its participants' student keys.
    private struct WorkEntry {
        let work: CDWorkModel
        let participantKeys: Set<String>
    }

    /// Exact (case-preserving) area + sequence, the arguments `find` receives.
    private struct SettingsKey: Hashable {
        let area: String
        let sequence: String
    }

    /// Staleness threshold: 14 weekdays (approx 2.8 calendar weeks)
    private static let staleWeekdays = 14

    /// Computes why a student is blocked from a lesson based on the preceding lesson's state.
    private static func computeBlockingReason(
        precedingLesson: CDLesson,
        rules: LessonProgressionRules.ResolvedRules?,
        studentID: UUID,
        studentKey: String,
        lasByLessonID: [String: [AssignmentEntry]],
        worksByLessonID: [String: [WorkEntry]]
    ) -> BlockingReason {
        guard let rules, rules.requiresPractice || rules.requiresTeacherConfirmation else {
            return .none
        }

        let precedingIDStr = precedingLesson.id?.uuidString ?? ""
        let precedingLAs = lasByLessonID[precedingIDStr] ?? []
        let presentedLA = precedingLAs.first {
            $0.assignment.isPresented && $0.studentKeys.contains(studentKey)
        }?.assignment

        guard let presentedLA else {
            // Preceding lesson hasn't been presented to this student
            return .prerequisiteNotPresented
        }

        var needsPractice = false
        var needsConfirmation = false

        if rules.requiresPractice {
            let precedingWorks = worksByLessonID[precedingIDStr] ?? []
            let studentWorks = precedingWorks.filter { $0.participantKeys.contains(studentKey) }
            let allComplete = !studentWorks.isEmpty && studentWorks.allSatisfy { $0.work.status.isClosed }
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

    /// Internal (not private) so the equivalence test can drive the legacy path through it.
    static func buildCellState(
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
        let isComplete = workModelForLesson?.status.isClosed == true
        let isWorkActive = studentWorkModels.contains { $0.status == WorkStatus.active }
        let isWorkReview = studentWorkModels.contains { $0.status == WorkStatus.review }

        // Compute staleness using pre-computed calendar & today (avoids per-cell allocation)
        let lastActivityDate = workModelForLesson?.lastTouchedAt ?? workModelForLesson?.createdAt
        let isStale: Bool = {
            guard !isComplete, let activity = lastActivityDate else { return false }
            // Clamped to the school-year counter epoch (see `SchoolYearCounters`), so work
            // resting since last spring isn't stale on the first day of school.
            let activityDay = calendar.startOfDay(for: SchoolYearCounters.countFrom(activity))
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
