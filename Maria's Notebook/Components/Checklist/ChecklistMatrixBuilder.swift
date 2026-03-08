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
        let lessonIDs = Set(lessons.map { $0.id })
        guard !lessonIDs.isEmpty else { return [:] }

        // Fetch LessonAssignments and filter to current lesson set
        let lessonIDStrings = Set(lessonIDs.uuidStrings)
        let laDescriptor = FetchDescriptor<LessonAssignment>()
        let allLAs = context.safeFetch(laDescriptor)
            .filter { lessonIDStrings.contains($0.lessonID) }

        // Fetch all WorkModels to track full lifecycle (active/review/complete)
        let workModelsDescriptor = FetchDescriptor<WorkModel>()
        let allWorkModels = context.safeFetch(workModelsDescriptor)

        var newMatrix: [UUID: [UUID: StudentChecklistRowState]] = [:]

        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            let studentLAs = allLAs.filter { $0.studentIDs.contains(student.cloudKitKey) }
            let studentIDString = student.cloudKitKey

            // Filter WorkModels for this student
            let studentWorkModels = allWorkModels.filter { work in
                (work.participants ?? []).contains { $0.studentID == studentIDString }
            }

            for lesson in lessons {
                let state = buildCellState(
                    student: student,
                    lesson: lesson,
                    studentLAs: studentLAs,
                    studentWorkModels: studentWorkModels
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
        student: Student,
        lesson: Lesson,
        studentLAs: [LessonAssignment],
        studentWorkModels: [WorkModel]
    ) -> StudentChecklistRowState {
        let lessonIDString = lesson.id.uuidString
        let lasForLesson = studentLAs.filter { $0.lessonID == lessonIDString }

        let nonPresented = lasForLesson.filter { !$0.isPresented }
        let plannedCandidate = nonPresented.first
        let isScheduled = !nonPresented.isEmpty

        // An inbox plan is scheduled but has no scheduledFor date
        let isInboxPlan = isScheduled && (plannedCandidate?.scheduledFor == nil)

        let isPresented = lasForLesson.contains { $0.isPresented }

        // Find WorkModels for this lesson
        let workModelsForLesson = studentWorkModels.filter { $0.lessonID == lessonIDString }
        let workModelForLesson = workModelsForLesson.first

        let isActive = workModelForLesson?.isOpen ?? false
        let isComplete = workModelForLesson?.status == .complete

        // Determine work lifecycle: active (practicing) vs review
        let isWorkActive = workModelsForLesson.contains { $0.status == .active }
        let isWorkReview = workModelsForLesson.contains { $0.status == .review }

        // Compute staleness: if lastTouchedAt is >14 weekdays ago and work is not complete
        let lastActivityDate = workModelForLesson?.lastTouchedAt ?? workModelForLesson?.createdAt
        let isStale: Bool = {
            guard !isComplete, let activity = lastActivityDate else { return false }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
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

        let contractID = workModelForLesson?.id

        return StudentChecklistRowState(
            lessonID: lesson.id,
            plannedItemID: plannedCandidate?.id,
            presentationLogID: nil,
            contractID: contractID,
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
