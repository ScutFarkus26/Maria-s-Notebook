import Foundation
import CoreData
import OSLog

/// Bridges the Year Plan (guide) with the Presentation calendar (truth).
/// Auto-promotes Year Plan entries when a new assignment is created,
/// scheduling it for the planned date if still in the future.
@MainActor
enum YearPlanPromotionService {
    private static let logger = Logger.app(category: "YearPlanPromotion")

    /// Called after PlanNextLessonService creates a draft assignment.
    /// Checks for a matching Year Plan entry and auto-promotes if the planned date is in the future.
    ///
    /// - Parameters:
    ///   - assignment: The newly created draft assignment.
    ///   - context: The managed object context.
    static func autoPromoteIfPlanExists(
        assignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) {
        let today = AppCalendar.startOfDay(Date())

        // For each student on this assignment, check for a matching Year Plan entry
        for studentID in assignment.studentUUIDs {
            guard let entry = findMatchingEntry(
                lessonID: assignment.lessonID,
                studentID: studentID,
                context: context
            ) else { continue }

            guard let plannedDate = entry.plannedDate else { continue }

            if plannedDate >= today {
                // Future or today: auto-schedule the assignment
                assignment.schedule(for: plannedDate)
                entry.status = .promoted
                entry.promotedAssignmentID = assignment.id?.uuidString
                logger.info("Auto-promoted entry for lesson \(assignment.lessonID) on \(plannedDate)")
            } else {
                // Past: don't auto-schedule, leave as draft, entry stays "planned" (behind pace)
                logger.info("Year Plan entry is behind pace for lesson \(assignment.lessonID) — flagging")
            }
        }
    }

    /// Manual promotion from Year Plan UI.
    /// Creates a new assignment and links it to the entry.
    @discardableResult
    static func promote(
        entry: CDYearPlanEntry,
        student: CDStudent,
        context: NSManagedObjectContext
    ) -> CDLessonAssignment? {
        guard let lessonID = UUID(uuidString: entry.lessonID),
              let studentID = student.id else { return nil }

        let assignment: CDLessonAssignment
        if let date = entry.plannedDate, date >= AppCalendar.startOfDay(Date()) {
            assignment = PresentationFactory.makeScheduled(
                lessonID: lessonID,
                studentIDs: [studentID],
                scheduledFor: date,
                context: context
            )
        } else {
            assignment = PresentationFactory.makeDraft(
                lessonID: lessonID,
                studentIDs: [studentID],
                context: context
            )
        }

        entry.status = .promoted
        entry.promotedAssignmentID = assignment.id?.uuidString
        entry.modifiedAt = Date()

        return assignment
    }

    // MARK: - Helpers

    /// Find a Year Plan entry matching a lesson + student that is still planned.
    private static func findMatchingEntry(
        lessonID: String,
        studentID: UUID,
        context: NSManagedObjectContext
    ) -> CDYearPlanEntry? {
        let req = CDFetchRequest(CDYearPlanEntry.self)
        req.predicate = NSPredicate(
            format: "lessonID == %@ AND studentID == %@ AND statusRaw == %@",
            lessonID, studentID.uuidString, YearPlanEntryStatus.planned.rawValue
        )
        req.fetchLimit = 1
        return context.safeFetchFirst(req)
    }
}
