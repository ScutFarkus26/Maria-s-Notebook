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

        // Fetch only non-complete WorkModels (active/review work)
        let workModelsDescriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { $0.statusRaw != "complete" }
        )
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

        // Find WorkModel for this lesson using lessonID directly
        let workModelForLesson = studentWorkModels.first { work in
            work.lessonID == lessonIDString
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
