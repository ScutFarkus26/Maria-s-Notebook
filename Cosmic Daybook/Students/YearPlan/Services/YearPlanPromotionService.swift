import Foundation
import CoreData
import OSLog

/// Bridges the Year Plan (guide) with the Presentation calendar (truth).
/// Auto-promotes Year Plan entries when a new assignment is created,
/// scheduling it for the planned date if still in the future.
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
        for studentID in assignment.resolvedStudentIDs {
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

    /// Returns the earliest planned date across all matching Year Plan entries for the
    /// given lesson + students. Read-only — does not promote.
    /// Used to pre-fill the Schedule date picker so the teacher sees the planned date
    /// as the default.
    static func plannedDate(
        lessonID: String,
        studentIDs: Set<UUID>,
        context: NSManagedObjectContext
    ) -> Date? {
        var dates: [Date] = []
        for studentID in studentIDs {
            if let entry = findMatchingEntry(lessonID: lessonID, studentID: studentID, context: context),
               let date = entry.plannedDate {
                dates.append(date)
            }
        }
        return dates.min()
    }

    // MARK: - Helpers

    /// Find a Year Plan entry matching a lesson + student that is still
    /// planned, and that the presentation record has not already answered.
    ///
    /// The second half matters when a guide schedules a lesson the child has
    /// already had: the old entry is settled, and promoting it would drag a
    /// finished intention onto the calendar as if it were the reason for the
    /// new plan. The new assignment stands on its own instead — which is what
    /// "give it again" means here.
    static func findMatchingEntry(
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
        guard let entry = context.safeFetchFirst(req) else { return nil }
        let satisfaction = YearPlanSatisfaction.index(for: [entry], in: context)
        return entry.isSatisfied(by: satisfaction) ? nil : entry
    }
}
