//
//  PracticeCheckInTiming.swift
//  Cosmic Daybook
//
//  When practice comes back (plan "Cut unused features and close the lesson
//  loop", Decisions › The lesson loop, 2026-11-21).
//
//  Practice set after a lesson is checked the school day before the next
//  lesson planned for that child in the same sequence, so the guide sees how
//  it went before she gives the next one. With nothing planned it comes back
//  three school days after the lesson.
//
//  - A new check-in is never earlier than the next school day after the
//    lesson, nor earlier than today: a lesson filed a week late still comes
//    back on a day that is still ahead.
//  - When a later lesson in the sequence is planned or moved for a child,
//    her open check-ins on earlier lessons in it that fall after the school
//    day before that lesson move to it. They only ever move earlier, never
//    to before today, and a check-in already done is left where it happened.
//
//  "Later in the sequence" is `WorkToShowFirst`'s "earlier", turned round, so
//  what the guide is warned about before a lesson is what comes back before
//  it. The school days are `SchoolDayChecker`'s. Nothing here saves.
//

import CoreData
import Foundation

enum PracticeCheckInTiming {

    /// School days after the lesson that practice comes back with no later
    /// lesson planned.
    static let schoolDaysWithNothingPlanned = 3

    // MARK: - A new check-in

    /// The day practice on `lessonID`, given on `givenOn`, is next checked for
    /// each of `studentIDs`.
    static func checkInDays(
        lessonID: String,
        givenOn: Date,
        studentIDs: Set<UUID>,
        sequences: WorkToShowFirst.Sequences,
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) -> [UUID: Date] {
        guard !studentIDs.isEmpty else { return [:] }
        let calendar = AppCalendar.shared
        let given = calendar.startOfDay(for: givenOn)
        let floor = max(
            SchoolDayChecker.schoolDay(from: given, forward: true, using: context) ?? given,
            calendar.startOfDay(for: now)
        )
        let fallback = max(threeSchoolDays(after: given, in: context), floor)
        let nextPlanned = nextPlannedLessonDays(
            after: lessonID, from: given, for: studentIDs, sequences: sequences, in: context
        )

        var days: [UUID: Date] = [:]
        for studentID in studentIDs {
            guard let lessonDay = nextPlanned[studentID] else {
                days[studentID] = fallback
                continue
            }
            days[studentID] = max(schoolDay(before: lessonDay, in: context), floor)
        }
        return days
    }

    /// Puts each child's open work from `presentationID` up for a check on
    /// her day in `days`: the earliest check-in still scheduled moves there
    /// when it is later, or one is made when she has none. Filing the same
    /// presentation again finds the check-in already there and makes no
    /// second one. Returns how many check-ins it made or moved.
    @discardableResult
    static func scheduleCheckIns(
        forWorkFrom presentationID: UUID,
        on days: [UUID: Date],
        in context: NSManagedObjectContext
    ) -> Int {
        guard !days.isEmpty else { return 0 }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID == %@", presentationID.uuidString)
        let service = WorkCheckInService(context: context)
        var count = 0
        for work in context.safeFetch(request) where !work.isDeleted && work.status.isOpen {
            guard let studentID = UUID(uuidString: work.studentID), let day = days[studentID] else { continue }
            let scheduled = WorkLogService.scheduledCheckIns(of: work, in: context)
            if let earliest = scheduled.compactMap(\.date).min(),
               AppCalendar.startOfDay(earliest) <= AppCalendar.startOfDay(day) {
                continue
            }
            if !scheduled.isEmpty {
                service.scheduleCheck(for: work, on: day)
            } else {
                CDWorkCheckIn.make(
                    for: work, on: day, purpose: CheckInReason.progressCheck.rawValue, in: context
                )
            }
            count += 1
        }
        return count
    }

    // MARK: - A later lesson planned or moved

    /// Pulls earlier open check-ins forward for the children of each waiting
    /// plan in `plans`, as the file header says. Call it after a plan's day or
    /// its children change. Returns how many check-ins moved.
    @discardableResult
    static func followPlannedLessons(
        _ plans: [CDLessonAssignment],
        sequences: WorkToShowFirst.Sequences? = nil,
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) -> Int {
        let waiting = plans.filter { !$0.isDeleted && !$0.isGiven && $0.scheduledFor != nil }
        guard !waiting.isEmpty else { return 0 }
        // Cheap first: nobody on these plans has a check-in waiting at all.
        let children = Set(waiting.flatMap(\.resolvedStudentIDs))
        guard hasOpenWork(for: children, in: context) else { return 0 }
        let sequences = sequences ?? WorkToShowFirst.Sequences(
            lessons: DataQueryService(context: context).fetchAllLessons()
        )

        var requests: [NSManagedObjectID: WorkToShowFirst.Request] = [:]
        for plan in waiting {
            requests[plan.objectID] = WorkToShowFirst.Request(
                lessonID: plan.resolvedLessonID.uuidString, studentIDs: Set(plan.resolvedStudentIDs)
            )
        }
        let found = WorkToShowFirst.find(requests, sequences: sequences, in: context)
        guard !found.isEmpty else { return 0 }

        var moved = 0
        for (work, target) in targetDays(for: waiting, found: found, in: context, now: now).values {
            for checkIn in WorkLogService.scheduledCheckIns(of: work, in: context) {
                guard let date = checkIn.date, AppCalendar.startOfDay(date) > target else { continue }
                WorkCheckInService.move(checkIn, toDay: target)
                moved += 1
            }
        }
        return moved
    }

    /// Each piece of earlier open work, with the day it should be checked by:
    /// the school day before the soonest plan in the call that it comes
    /// before, never before today.
    private static func targetDays(
        for plans: [CDLessonAssignment],
        found: [NSManagedObjectID: WorkToShowFirst.ByChild],
        in context: NSManagedObjectContext,
        now: Date
    ) -> [NSManagedObjectID: (work: CDWorkModel, day: Date)] {
        let today = AppCalendar.startOfDay(now)
        var targets: [NSManagedObjectID: (work: CDWorkModel, day: Date)] = [:]
        for plan in plans {
            guard let byChild = found[plan.objectID], let scheduled = plan.scheduledFor else { continue }
            let target = max(schoolDay(before: scheduled, in: context), today)
            for item in byChild.values.joined() {
                if let held = targets[item.work.objectID], held.day <= target { continue }
                targets[item.work.objectID] = (item.work, target)
            }
        }
        return targets
    }
    // MARK: - Reading

    /// Each child's next waiting plan, by day, for a lesson later than
    /// `lessonID` in its sequence and on or after `day`.
    static func nextPlannedLessonDays(
        after lessonID: String,
        from day: Date,
        for studentIDs: Set<UUID>,
        sequences: WorkToShowFirst.Sequences,
        in context: NSManagedObjectContext
    ) -> [UUID: Date] {
        let later = laterLessonIDs(after: lessonID, in: sequences)
        guard !later.isEmpty else { return [:] }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "lessonID IN %@ AND scheduledFor >= %@",
            Array(later), AppCalendar.startOfDay(day) as NSDate
        )
        var days: [UUID: Date] = [:]
        for plan in context.safeFetch(request) where !plan.isDeleted && !plan.isGiven {
            guard let scheduled = plan.scheduledFor else { continue }
            let planDay = AppCalendar.startOfDay(scheduled)
            for studentID in plan.resolvedStudentIDs where studentIDs.contains(studentID) {
                if let held = days[studentID], held <= planDay { continue }
                days[studentID] = planDay
            }
        }
        return days
    }

    /// The lessons in `lessonID`'s sequence that it comes before, as
    /// `WorkToShowFirst.earlierLessonIDs` judges "before".
    static func laterLessonIDs(after lessonID: String, in sequences: WorkToShowFirst.Sequences) -> Set<String> {
        guard let position = sequences.order.position(of: lessonID) else { return [] }
        let ids = sequences.order.lessonIDs(area: position.area, sequence: position.sequence)
        return Set(ids.filter { id in
            id != lessonID && WorkToShowFirst.earlierLessonIDs(before: id, in: sequences).contains(lessonID)
        })
    }

    /// The school day before `day`'s, or that day itself when none is found.
    static func schoolDay(before day: Date, in context: NSManagedObjectContext) -> Date {
        let start = AppCalendar.startOfDay(day)
        return SchoolDayChecker.schoolDay(from: start, forward: false, using: context) ?? start
    }

    private static func threeSchoolDays(after day: Date, in context: NSManagedObjectContext) -> Date {
        var cursor = day
        for _ in 0..<schoolDaysWithNothingPlanned {
            cursor = SchoolDayChecker.schoolDay(from: cursor, forward: true, using: context) ?? cursor
        }
        return cursor
    }

    /// Whether any of `studentIDs` owns or shares open work at all.
    private static func hasOpenWork(for studentIDs: Set<UUID>, in context: NSManagedObjectContext) -> Bool {
        guard !studentIDs.isEmpty else { return false }
        let ids = studentIDs.map(\.uuidString)
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            WorkStatus.openPredicate,
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "studentID IN %@", ids),
                NSPredicate(format: "ANY participants.studentID IN %@", ids)
            ])
        ])
        request.fetchLimit = 1
        return !context.safeFetch(request).isEmpty
    }
}
