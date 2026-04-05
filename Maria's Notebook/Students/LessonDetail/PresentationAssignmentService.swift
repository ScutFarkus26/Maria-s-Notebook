import Foundation
import OSLog
import CoreData

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
    ///   - viewContext: Model context for database operations
    static func createFollowUpAssignments(
        _ assignments: [PostPresentationAssignmentsSheet.AssignmentEntry],
        lessonID: UUID,
        viewContext: NSManagedObjectContext
    ) {
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue
        let followRaw = WorkKind.followUpAssignment.rawValue

        for entry in assignments {
            let studentUUID = entry.studentID

            // Fetch all WorkModels and filter in memory (no predicates)
            let allWorkModels: [CDWorkModel]
            do {
                allWorkModels = try viewContext.fetch(NSFetchRequest<CDWorkModel>(entityName: "WorkModel"))
            } catch {
                logger.warning("Failed to fetch WorkModels: \(error)")
                allWorkModels = []
            }

            // Find existing CDWorkModel for this student/lesson with follow-up kind
            let lessonIDString = lessonID.uuidString
            let existingWork = allWorkModels.first { work in
                // Check if student is a participant
                let participantsArray = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
                let hasStudent = participantsArray.contains { $0.studentID == studentUUID.uuidString }
                guard hasStudent else { return false }

                // Check if work is for this lesson
                guard work.lessonID == lessonIDString else { return false }

                // Check status and kind
                return (work.statusRaw == activeRaw || work.statusRaw == reviewRaw) &&
                       (work.kindRaw ?? "") == followRaw
            }

            // Get user-entered assignment name
            let trimmed = entry.text.trimmed()

            if let existing = existingWork {
                // Update notes if provided (unified notes)
                if !trimmed.isEmpty {
                    Task { @MainActor in
                        existing.setLegacyNoteText(trimmed, in: viewContext)
                    }
                }
                // Schedule check-in if provided
                if let sched = entry.schedule {
                    scheduleCheckIn(for: existing, schedule: sched, context: viewContext)
                }
            } else {
                // Create new CDWorkModel via Core Data repository
                let repository = WorkRepository(context: viewContext)
                do {
                    let cdWork = try repository.createWork(
                        studentID: studentUUID,
                        lessonID: lessonID,
                        title: trimmed,
                        kind: WorkKind.followUpAssignment,
                        presentationID: nil as UUID?,
                        scheduledDate: nil as Date?
                    )
                    // Update notes if provided (unified notes)
                    if !trimmed.isEmpty {
                        cdWork.setLegacyNoteText(trimmed, in: repository.context)
                    }
                    // Schedule check-in if provided
                    if let sched = entry.schedule {
                        scheduleCheckIn(for: cdWork, schedule: sched, context: repository.context)
                    }
                } catch {
                    logger.warning("Failed to create work: \(error)")
                    continue
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// Schedules a check-in for a CD work item.
    private static func scheduleCheckIn(
        for work: CDWorkModel,
        schedule: PostPresentationAssignmentsSheet.Schedule,
        context: NSManagedObjectContext
    ) {
        let normalized = AppCalendar.startOfDay(schedule.date)
        let checkInKind = PostPresentationAssignmentsSheet.ScheduleKind.checkIn

        // Check if check-in already exists
        let existingCheckIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
        let hasCheckIn = existingCheckIns.contains { checkIn in
            AppCalendar.startOfDay(checkIn.date ?? Date()) == normalized && checkIn.statusRaw == WorkCheckInStatus.scheduled.rawValue
        }

        if !hasCheckIn {
            let purpose: String = (schedule.kind == checkInKind) ? "Progress check" : "Due date"
            let checkIn = CDWorkCheckIn(context: context)
            checkIn.workID = work.id?.uuidString ?? ""
            checkIn.date = normalized
            checkIn.statusRaw = WorkCheckInStatus.scheduled.rawValue
            checkIn.purpose = purpose
            checkIn.work = work
        }
    }

    /// Schedules a check-in for a work item.
    @available(*, deprecated, message: "Use scheduleCheckIn(for:schedule:context:) with CDWorkModel")
    private static func scheduleCheckIn(
        for work: CDWorkModel,
        schedule: PostPresentationAssignmentsSheet.Schedule,
        viewContext: NSManagedObjectContext
    ) {
        let normalized = AppCalendar.startOfDay(schedule.date)
        let checkInKind = PostPresentationAssignmentsSheet.ScheduleKind.checkIn

        // Check if check-in already exists
        let existingCheckIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
        let hasCheckIn = existingCheckIns.contains { (checkIn: CDWorkCheckIn) in
            AppCalendar.startOfDay(checkIn.date ?? Date()) == normalized && checkIn.status == .scheduled
        }

        if !hasCheckIn {
            let purpose: String = (schedule.kind == checkInKind) ? "Progress check" : "Due date"
            let checkIn = CDWorkCheckIn(context: viewContext)
            checkIn.workID = work.id?.uuidString ?? ""
            checkIn.date = normalized
            checkIn.statusRaw = WorkCheckInStatus.scheduled.rawValue
            checkIn.purpose = purpose
            checkIn.work = work
        }
    }
}
