import Foundation
import SwiftData

// MARK: - Student Lesson Assignment Service

/// Service for creating follow-up assignments after lesson presentations.
enum StudentLessonAssignmentService {

    // MARK: - Create Follow-Up Assignments

    /// Creates follow-up assignments for students after a lesson presentation.
    ///
    /// - Parameters:
    ///   - assignments: Array of assignment entries from the composer sheet
    ///   - lessonID: The lesson ID to associate with the assignments
    ///   - studentLessonsAll: All student lessons for lookup
    ///   - modelContext: Model context for database operations
    static func createFollowUpAssignments(
        _ assignments: [PostPresentationAssignmentsSheet.AssignmentEntry],
        lessonID: UUID,
        studentLessonsAll: [StudentLesson],
        modelContext: ModelContext
    ) {
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue
        let followRaw = WorkKind.followUpAssignment.rawValue

        for entry in assignments {
            let studentUUID = entry.studentID

            // Fetch all WorkModels and filter in memory (no predicates)
            let allWorkModels = (try? modelContext.fetch(FetchDescriptor<WorkModel>())) ?? []

            // Find existing WorkModel for this student/lesson with follow-up kind
            let existingWork = allWorkModels.first { work in
                // Check if student is a participant
                let hasStudent = (work.participants ?? []).contains { $0.studentID == studentUUID.uuidString }
                guard hasStudent else { return false }

                // Check if work is for this lesson (via studentLessonID)
                guard let slID = work.studentLessonID,
                      let sl = studentLessonsAll.first(where: { $0.id == slID }),
                      UUID(uuidString: sl.lessonID) == lessonID else {
                    return false
                }

                // Check status and kind
                return (work.statusRaw == activeRaw || work.statusRaw == reviewRaw) &&
                       (work.kindRaw ?? "") == followRaw
            }

            // Get user-entered assignment name
            let trimmed = entry.text.trimmed()

            let work: WorkModel
            if let existing = existingWork {
                work = existing
            } else {
                // Create new WorkModel
                let repository = WorkRepository(context: modelContext)
                guard let created = try? repository.createWork(
                    studentID: studentUUID,
                    lessonID: lessonID,
                    title: trimmed,
                    kind: .followUpAssignment,
                    presentationID: nil,
                    scheduledDate: nil
                ) else {
                    continue
                }
                work = created
            }

            // Update notes if provided
            if !trimmed.isEmpty {
                work.notes = trimmed
            }

            // Schedule check-in if provided
            if let sched = entry.schedule {
                scheduleCheckIn(for: work, schedule: sched, modelContext: modelContext)
            }
        }
    }

    // MARK: - Private Helpers

    /// Schedules a check-in for a work item.
    private static func scheduleCheckIn(
        for work: WorkModel,
        schedule: PostPresentationAssignmentsSheet.Schedule,
        modelContext: ModelContext
    ) {
        let normalized = AppCalendar.startOfDay(schedule.date)
        let checkInKind = PostPresentationAssignmentsSheet.ScheduleKind.checkIn

        // Check if check-in already exists
        let existingCheckIns = work.checkIns ?? []
        let hasCheckIn = existingCheckIns.contains { checkIn in
            AppCalendar.startOfDay(checkIn.date) == normalized && checkIn.status == .scheduled
        }

        if !hasCheckIn {
            let purpose: String = (schedule.kind == checkInKind) ? "Progress check" : "Due date"
            let checkIn = WorkCheckIn(
                workID: work.id,
                date: normalized,
                status: .scheduled,
                purpose: purpose,
                note: "",
                work: work
            )
            modelContext.insert(checkIn)
            if work.checkIns == nil { work.checkIns = [] }
            work.checkIns = (work.checkIns ?? []) + [checkIn]
        }
    }
}
