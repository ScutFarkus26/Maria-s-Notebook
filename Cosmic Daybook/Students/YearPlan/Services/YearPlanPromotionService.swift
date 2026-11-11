import Foundation
import CoreData
import OSLog

/// Bridges the Year Plan (guide) with the Presentation calendar (truth).
/// Auto-promotes Year Plan entries when a new assignment is created,
/// scheduling it for the planned date if still in the future.
enum YearPlanPromotionService {
    private static let logger = Logger.yearPlanPromotion

    /// Called after PlanNextLessonService creates a draft assignment.
    /// Checks the children's matching Year Plan entries and, when any is planned
    /// for today or later, schedules the draft for the earliest of those days and
    /// promotes every child's entry into it on that day.
    ///
    /// One day for the whole group: this used to schedule the draft to each
    /// child's date in turn, so it landed on whichever came last while the
    /// others' entries kept their own dates (bug hunt 2026-11-03 #20). A plan
    /// whose entries are all behind pace stays a draft, as before.
    ///
    /// - Parameters:
    ///   - assignment: The newly created draft assignment.
    ///   - context: The managed object context.
    static func autoPromoteIfPlanExists(
        assignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) {
        let today = AppCalendar.startOfDay(Date())
        let plannedDates = assignment.resolvedStudentIDs.compactMap { studentID in
            findMatchingEntry(lessonID: assignment.lessonID, studentID: studentID, context: context)?.plannedDate
        }
        guard let day = plannedDates.filter({ $0 >= today }).min() else {
            if !plannedDates.isEmpty {
                // Past: don't auto-schedule, leave as draft, entries stay "planned" (behind pace)
                logger.info("Year Plan entry is behind pace for lesson \(assignment.lessonID) — flagging")
            }
            return
        }
        // A planned date is a day, not a time: the draft takes its place in the
        // morning rather than reading whatever clock time the entry carries as
        // a set time (plan "Lesson times on cards", decision 4).
        assignment.schedule(onDay: day)
        let promoted = promoteMatchingEntries(into: assignment, scheduledFor: day, context: context)
        logger.info("Auto-promoted \(promoted) entries for lesson \(assignment.lessonID) on \(day)")
    }

    /// Promotes each child's matching planned entry into `assignment`, leaving
    /// the day the assignment was given alone — for a caller that has already
    /// chosen the day (MCP's `schedule_presentation`). Returns how many
    /// entries were promoted. Does not save.
    @discardableResult
    static func promoteMatchingEntries(
        into assignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) -> Int {
        assignment.resolvedStudentIDs.filter {
            promoteMatchingEntry(for: $0, into: assignment, context: context)
        }.count
    }

    /// A presentation put on a day: each child's still-planned entry for the
    /// lesson is promoted into it and moved to that day, so the year plan shows
    /// it where the calendar does. An entry already promoted into it follows it
    /// to the new day; a later move used to leave it on the day it was first
    /// promoted for, drawn there as Promoted and then Given on a day nothing
    /// happened (bug hunt 2026-11-03 #20). It lays nothing on the lessons
    /// after. Until 2026-11-03 scheduling one lesson also wrote an entry on
    /// every later lesson of its sequence (`SequenceAutoPopulateService`,
    /// three school days apart), which dressed whole strands Planned on the
    /// Checklist and kept each child out of Ready for lessons she hadn't
    /// reached; Add Sequence on the year plan is the way to lay one out on
    /// purpose. Returns how many entries were promoted or moved. Does not save.
    @discardableResult
    static func promoteMatchingEntries(
        into assignment: CDLessonAssignment,
        scheduledFor day: Date,
        context: NSManagedObjectContext
    ) -> Int {
        guard let assignmentID = assignment.id?.uuidString else { return 0 }
        let planned = AppCalendar.startOfDay(day)
        let promoted = assignment.resolvedStudentIDs.filter { studentID in
            guard let entry = findMatchingEntry(
                lessonID: assignment.lessonID, studentID: studentID, context: context
            ) else { return false }
            entry.status = .promoted
            entry.promotedAssignmentID = assignmentID
            entry.plannedDate = planned
            return true
        }.count
        return promoted + moveEntries(promotedInto: assignmentID, to: planned, context: context)
    }

    /// Moves the entries promoted into the presentation `assignmentID` to
    /// `day`, the presentation's own. Only those not already there change.
    /// Returns how many moved. Does not save.
    @discardableResult
    static func moveEntries(
        promotedInto assignmentID: String,
        to day: Date,
        context: NSManagedObjectContext
    ) -> Int {
        let req = CDFetchRequest(CDYearPlanEntry.self)
        req.predicate = NSPredicate(
            format: "promotedAssignmentID == %@ AND statusRaw == %@",
            assignmentID, YearPlanEntryStatus.promoted.rawValue
        )
        var moved = 0
        for entry in context.safeFetch(req) where !entry.isDeleted && entry.plannedDate != day {
            entry.plannedDate = day
            entry.modifiedAt = Date()
            moved += 1
        }
        return moved
    }

    /// Promotes one child's matching planned entry into `assignment`, for a
    /// caller that puts her on a plan other children may already be on (the
    /// Checklist's Inbox toggle), so their entries are left as they are.
    /// Returns whether one was promoted. Does not save.
    @discardableResult
    static func promoteMatchingEntry(
        for studentID: UUID,
        into assignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) -> Bool {
        guard let assignmentID = assignment.id?.uuidString,
              let entry = findMatchingEntry(lessonID: assignment.lessonID, studentID: studentID, context: context)
        else { return false }
        entry.status = .promoted
        entry.promotedAssignmentID = assignmentID
        return true
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
