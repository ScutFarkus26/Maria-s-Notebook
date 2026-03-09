import Foundation
import SwiftData

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
        students: [Student],
        lessons: [Lesson],
        context: ModelContext
    ) -> [UUID: [UUID: StudentChecklistRowState]] {
        let lessonIDStrings = Set(lessons.map { $0.id.uuidString })
        guard !lessonIDStrings.isEmpty else { return [:] }

        // Fetch LessonAssignments scoped to current lessons.
        // LessonAssignment has an #Index on lessonID, so per-lesson predicates are fast.
        // We batch fetches by lesson to leverage the index rather than fetching all records.
        var lasByLessonID: [String: [LessonAssignment]] = [:]
        for lessonIDString in lessonIDStrings {
            let descriptor = FetchDescriptor<LessonAssignment>(
                predicate: #Predicate { $0.lessonID == lessonIDString }
            )
            lasByLessonID[lessonIDString] = context.safeFetch(descriptor)
        }

        // Fetch WorkModels scoped to current lessons using studentID index.
        // Build a lookup by lessonID for O(1) access per cell.
        var worksByLessonID: [String: [WorkModel]] = [:]
        for lessonIDString in lessonIDStrings {
            let descriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate { $0.lessonID == lessonIDString }
            )
            worksByLessonID[lessonIDString] = context.safeFetch(descriptor)
        }

        var newMatrix: [UUID: [UUID: StudentChecklistRowState]] = [:]

        // Pre-compute staleness threshold date once instead of per-cell
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            let studentKey = student.cloudKitKey

            for lesson in lessons {
                let lessonIDString = lesson.id.uuidString
                let lasForLesson = lasByLessonID[lessonIDString] ?? []
                let studentLAs = lasForLesson.filter { $0.studentIDs.contains(studentKey) }
                let worksForLesson = worksByLessonID[lessonIDString] ?? []
                let studentWorks = worksForLesson.filter { work in
                    (work.participants ?? []).contains { $0.studentID == studentKey }
                }

                let state = buildCellState(
                    lesson: lesson,
                    studentLAs: studentLAs,
                    studentWorkModels: studentWorks,
                    calendar: calendar,
                    today: today
                )
                studentRow[lesson.id] = state
            }
            newMatrix[student.id] = studentRow
        }

        return newMatrix
    }

    // MARK: - Private Helpers

    /// Staleness threshold: 14 weekdays (approx 2.8 calendar weeks)
    private static let staleWeekdays = 14

    private static func buildCellState(
        lesson: Lesson,
        studentLAs: [LessonAssignment],
        studentWorkModels: [WorkModel],
        calendar: Calendar,
        today: Date
    ) -> StudentChecklistRowState {
        let nonPresented = studentLAs.filter { !$0.isPresented }
        let plannedCandidate = nonPresented.first
        let isScheduled = !nonPresented.isEmpty
        let isInboxPlan = isScheduled && (plannedCandidate?.scheduledFor == nil)
        let isPresented = studentLAs.contains { $0.isPresented }

        let workModelForLesson = studentWorkModels.first
        let isActive = workModelForLesson?.isOpen ?? false
        let isComplete = workModelForLesson?.status == .complete
        let isWorkActive = studentWorkModels.contains { $0.status == .active }
        let isWorkReview = studentWorkModels.contains { $0.status == .review }

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
            lessonID: lesson.id,
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
            isInboxPlan: isInboxPlan
        )
    }
}
