import Foundation
import SwiftData
import OSLog

// MARK: - Presentation Assignment Service

/// Service for creating follow-up assignments after lesson presentations.
@MainActor
enum PresentationAssignmentService {
    private static let logger = Logger.students

    // MARK: - Create Follow-Up Assignments

    /// Creates follow-up assignments for students after a lesson presentation.
    ///
    /// - Parameters:
    ///   - assignments: Array of assignment entries from the composer sheet
    ///   - lessonID: The lesson ID to associate with the assignments
    ///   - modelContext: Model context for database operations
    static func createFollowUpAssignments(
        _ assignments: [PostPresentationAssignmentsSheet.AssignmentEntry],
        lessonID: UUID,
        modelContext: ModelContext
    ) {
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue
        let followRaw = WorkKind.followUpAssignment.rawValue

        for entry in assignments {
            let studentUUID = entry.studentID

            // Fetch all WorkModels and filter in memory (no predicates)
            let allWorkModels: [WorkModel]
            do {
                allWorkModels = try modelContext.fetch(FetchDescriptor<WorkModel>())
            } catch {
                logger.warning("Failed to fetch WorkModels: \(error)")
                allWorkModels = []
            }

            // Find existing WorkModel for this student/lesson with follow-up kind
            let lessonIDString = lessonID.uuidString
            let existingWork = allWorkModels.first { work in
                // Check if student is a participant
                let hasStudent = (work.participants ?? []).contains { $0.studentID == studentUUID.uuidString }
                guard hasStudent else { return false }

                // Check if work is for this lesson
                guard work.lessonID == lessonIDString else { return false }

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
                do {
                    work = try repository.createWork(
                        studentID: studentUUID,
                        lessonID: lessonID,
                        title: trimmed,
                        kind: .followUpAssignment,
                        presentationID: nil,
                        scheduledDate: nil
                    )
                } catch {
                    logger.warning("Failed to create work: \(error)")
                    continue
                }
            }

            // Update notes if provided (unified notes)
            if !trimmed.isEmpty {
                Task { @MainActor in
                    work.setLegacyNoteText(trimmed, in: modelContext)
                }
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
                work: work
            )
            modelContext.insert(checkIn)
            if work.checkIns == nil { work.checkIns = [] }
            work.checkIns = (work.checkIns ?? []) + [checkIn]
        }
    }
}
