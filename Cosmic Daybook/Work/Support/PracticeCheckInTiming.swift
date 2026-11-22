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
//  - A plan being recorded in the same call (a chat call that files two
//    lessons of one sequence) isn't a lesson still to come, so it doesn't
//    time the earlier lesson's practice.
//  - Work that already has a check-in keeps it: filing the same lesson again
//    leaves a check-in moved later by hand where it is, and adds nothing
//    after a done one. Only new work gets one.
//  - When a later lesson in the sequence is planned or moved for a child,
//    and none of her open work's check-ins on an earlier lesson falls by the
//    school day before it, the earliest one moves there. Only that one moves
//    (a later check on the same work keeps its day), a due-date check never
//    moves (it is the work's deadline), and a check-in already done is left
//    where it happened. A moved one only ever moves earlier, and never to
//    before the first school day from today, nor before the next school day
//    after the work was set: practice given today isn't checked today.
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
    ///
    /// - Parameter recordedNow: lessons being recorded in the same call, each
    ///   with the children it is recorded for. A waiting plan for one of them
    ///   is being given, not still to come, so it times nobody's practice.
    static func checkInDays(
        lessonID: String,
        givenOn: Date,
        studentIDs: Set<UUID>,
        sequences: WorkToShowFirst.Sequences,
        recordedNow: [UUID: Set<UUID>] = [:],
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) -> [UUID: Date] {
        guard !studentIDs.isEmpty else { return [:] }
        let calendar = AppCalendar.shared
        let given = calendar.startOfDay(for: givenOn)
        let floor = max(
            SchoolDayChecker.schoolDay(from: given, forward: true, using: context) ?? given,
            schoolDay(onOrAfter: now, in: context)
        )
        let fallback = max(threeSchoolDays(after: given, in: context), floor)
        let nextPlanned = nextPlannedLessonDays(
            after: lessonID, from: given, for: studentIDs, sequences: sequences,
            recordedNow: recordedNow, in: context
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

    /// Gives each child's open work from `presentationID` a check-in on her
    /// day in `days`, when the work has none yet. Work that already has one,
    /// scheduled or done, keeps what it has: filing the same presentation
    /// again leaves a check-in the guide moved where she put it, and adds
    /// nothing after one already done. Returns how many check-ins it made.
    @discardableResult
    static func scheduleCheckIns(
        forWorkFrom presentationID: UUID,
        on days: [UUID: Date],
        in context: NSManagedObjectContext
    ) -> Int {
        guard !days.isEmpty else { return 0 }
        var count = 0
        for work in openWork(from: presentationID, in: context) {
            guard let studentID = UUID(uuidString: work.studentID), let day = days[studentID],
                  WorkLogService.checkIns(of: work, in: context).isEmpty else { continue }
            CDWorkCheckIn.make(for: work, on: day, purpose: CheckInReason.progressCheck.rawValue, in: context)
            count += 1
        }
        return count
    }

    /// `days`, with each child whose work from `presentationID` already has a
    /// check-in given the day she is already checked instead: her earliest
    /// one still scheduled, else her follow-up row's day (nothing when it has
    /// none). Her follow-up row then keeps the day her check-in kept.
    static func keepingDaysAlreadySet(
        _ days: [UUID: Date], forWorkFrom presentationID: UUID, in context: NSManagedObjectContext
    ) -> [UUID: Date] {
        var kept = days
        var rows: [String: CDLessonPresentation]?
        for work in openWork(from: presentationID, in: context) {
            guard let studentID = UUID(uuidString: work.studentID), days[studentID] != nil else { continue }
            let checkIns = WorkLogService.checkIns(of: work, in: context)
            guard !checkIns.isEmpty else { continue }
            if let scheduled = checkIns.filter({ $0.status == .scheduled }).compactMap(\.date).min() {
                kept[studentID] = AppCalendar.startOfDay(scheduled)
                continue
            }
            if rows == nil {
                rows = Dictionary(
                    PresentationFollowUpService.rows(for: presentationID, in: context).map { ($0.studentID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
            kept[studentID] = rows?[work.studentID]?.followUpReviewAt.map(AppCalendar.startOfDay)
        }
        return kept
    }

    private static func openWork(from presentationID: UUID, in context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID == %@", presentationID.uuidString)
        return context.safeFetch(request).filter { !$0.isDeleted && $0.status.isOpen }
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
        for (work, planDay) in targetDays(for: waiting, found: found, in: context, now: now).values {
            let target = max(planDay, dayAfterSetting(work, in: context))
            let scheduled = WorkLogService.scheduledCheckIns(of: work, in: context)
                .filter { $0.date != nil }
            // Already looked at by then: nothing to bring forward.
            if scheduled.contains(where: { AppCalendar.startOfDay($0.date ?? target) <= target }) { continue }
            guard let earliest = scheduled
                .filter({ !WorkCheckInService.isDueDateCheck($0) })
                .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) })
            else { continue }
            WorkCheckInService.move(earliest, toDay: target)
            moved += 1
        }
        return moved
    }

    /// The next school day after `work` was set, so practice given today
    /// isn't pulled back to today; the distant past when it has no date.
    private static func dayAfterSetting(_ work: CDWorkModel, in context: NSManagedObjectContext) -> Date {
        guard let set = work.assignedAt ?? work.createdAt else { return .distantPast }
        let start = AppCalendar.startOfDay(set)
        return SchoolDayChecker.schoolDay(from: start, forward: true, using: context) ?? start
    }

    /// Each piece of earlier open work, with the day it should be checked by:
    /// the school day before the soonest plan in the call that it comes
    /// before, never before the first school day from today.
    private static func targetDays(
        for plans: [CDLessonAssignment],
        found: [NSManagedObjectID: WorkToShowFirst.ByChild],
        in context: NSManagedObjectContext,
        now: Date
    ) -> [NSManagedObjectID: (work: CDWorkModel, day: Date)] {
        let today = schoolDay(onOrAfter: now, in: context)
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
    /// `lessonID` in its sequence and on or after `day`, leaving out a child's
    /// place on a plan whose lesson `recordedNow` is recording for her.
    static func nextPlannedLessonDays(
        after lessonID: String,
        from day: Date,
        for studentIDs: Set<UUID>,
        sequences: WorkToShowFirst.Sequences,
        recordedNow: [UUID: Set<UUID>] = [:],
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
            let beingGiven = recordedNow[plan.resolvedLessonID] ?? []
            for studentID in plan.resolvedStudentIDs
            where studentIDs.contains(studentID) && !beingGiven.contains(studentID) {
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

    /// `day` itself when it is a school day, else the next one.
    static func schoolDay(onOrAfter day: Date, in context: NSManagedObjectContext) -> Date {
        let start = AppCalendar.startOfDay(day)
        if SchoolDayChecker.isSchoolDay(start, using: context) { return start }
        return SchoolDayChecker.schoolDay(from: start, forward: true, using: context) ?? start
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
