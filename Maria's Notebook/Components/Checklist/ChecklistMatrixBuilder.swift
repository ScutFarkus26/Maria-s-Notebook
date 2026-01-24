import Foundation
import SwiftData

// MARK: - Checklist Matrix Builder

/// Builds the matrix of student/lesson states for the checklist grid.
/// Computes status for each cell based on StudentLessons and WorkModels.
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

        // CloudKit compatibility: Convert UUIDs to strings for comparison
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        let lessonIDStrings = Set(lessonIDs.map { $0.uuidString })
        let allStudentLessons = context.safeFetch(FetchDescriptor<StudentLesson>())
        let allSLs = allStudentLessons.filter { lessonIDStrings.contains($0.lessonID) }

        // Fetch all WorkModels and filter in memory
        let allWorkModels = context.safeFetch(FetchDescriptor<WorkModel>())

        var newMatrix: [UUID: [UUID: StudentChecklistRowState]] = [:]

        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            let studentSLs = allSLs.filter { $0.studentIDs.contains(student.id.uuidString) }
            let studentIDString = student.id.uuidString

            // Filter WorkModels for this student
            let studentWorkModels = allWorkModels.filter { work in
                (work.participants ?? []).contains { $0.studentID == studentIDString }
            }

            for lesson in lessons {
                let state = buildCellState(
                    student: student,
                    lesson: lesson,
                    studentSLs: studentSLs,
                    studentWorkModels: studentWorkModels
                )
                studentRow[lesson.id] = state
            }
            newMatrix[student.id] = studentRow
        }

        return newMatrix
    }

    // MARK: - Private Helpers

    private static func buildCellState(
        student: Student,
        lesson: Lesson,
        studentSLs: [StudentLesson],
        studentWorkModels: [WorkModel]
    ) -> StudentChecklistRowState {
        let lessonIDString = lesson.id.uuidString
        let slsForLesson = studentSLs.filter { $0.lessonID == lessonIDString }

        let nonGiven = slsForLesson.filter { !$0.isGiven }
        let plannedCandidate = nonGiven.first
        let isScheduled = !nonGiven.isEmpty

        // Compute isInboxPlan here instead of per-cell render
        // An inbox plan is scheduled but has no scheduledFor date
        let isInboxPlan = isScheduled && (plannedCandidate?.scheduledFor == nil)

        let isPresented = slsForLesson.contains { $0.isGiven }

        // Find WorkModel for this lesson
        let workModelForLesson = studentWorkModels.first { work in
            guard let slID = work.studentLessonID,
                  let sl = studentSLs.first(where: { $0.id == slID }),
                  UUID(uuidString: sl.lessonID) == lesson.id else {
                return false
            }
            return true
        }

        let isActive = workModelForLesson?.isOpen ?? false
        let isComplete = workModelForLesson?.status == .complete

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
            lastActivityDate: nil,
            isStale: false,
            isInboxPlan: isInboxPlan
        )
    }
}
