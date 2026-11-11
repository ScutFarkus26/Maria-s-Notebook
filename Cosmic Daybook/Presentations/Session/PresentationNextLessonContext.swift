// PresentationNextLessonContext.swift
// What the presentation sheet has to know about the lesson after this one to
// say truthfully where it will go: its name, who is already on a plan for it,
// and whether the year plan already has a day for it
// (docs/Plans/Plan - Next lesson row when presenting.md, decision 4).
//
// Read once when How It Went opens. Done reads the same plans again through
// `unpresentedPlans`, so the row and the commit agree on who needs a new plan.

import CoreData
import Foundation

struct PresentationNextLessonContext: Equatable {
    let lessonID: UUID
    let lessonName: String
    /// Children already on a plan for it that has not been given.
    let alreadyPlanned: Set<UUID>
    /// Each child's year-plan day for it, when that day is today or later.
    let yearPlanDays: [UUID: Date]

    /// Nil when `lesson` is the last of its sequence.
    static func load(
        after lesson: CDLesson,
        lessons: [CDLesson],
        studentIDs: [UUID],
        context: NSManagedObjectContext,
        today: Date = Date()
    ) -> Self? {
        guard let next = PlanNextLessonService.findNextLesson(after: lesson, in: lessons),
              let nextID = next.id else { return nil }
        let startOfToday = AppCalendar.startOfDay(today)
        var days: [UUID: Date] = [:]
        for studentID in studentIDs {
            guard let planned = YearPlanPromotionService.findMatchingEntry(
                lessonID: nextID.uuidString, studentID: studentID, context: context
            )?.plannedDate, planned >= startOfToday else { continue }
            days[studentID] = AppCalendar.startOfDay(planned)
        }
        return Self(
            lessonID: nextID,
            lessonName: next.name,
            alreadyPlanned: Set(unpresentedPlans(for: nextID, in: context).flatMap(\.resolvedStudentIDs)),
            yearPlanDays: days
        )
    }

    /// The plans for a lesson that have not been given: in the Inbox or on a day.
    static func unpresentedPlans(
        for lessonID: UUID,
        in context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        return context.safeFetch(request).filter { !$0.isPresented && !$0.isDeleted }
    }

    /// The newly ready children Done makes a plan for: those not on one already.
    func recipients(newlyReady: Set<UUID>) -> Set<UUID> {
        newlyReady.subtracting(alreadyPlanned)
    }

    /// Where the lesson goes if the guide chooses nothing: the earliest day
    /// the year plan has it on for any of these children, otherwise the Inbox.
    func startingPlace(for recipients: Set<UUID>) -> PresentationNextLessonPlace {
        guard let day = recipients.compactMap({ yearPlanDays[$0] }).min() else { return .inbox }
        return PresentationNextLessonPlace(day: day)
    }
}
