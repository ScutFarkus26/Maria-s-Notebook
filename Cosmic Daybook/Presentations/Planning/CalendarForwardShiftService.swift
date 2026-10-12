// CalendarForwardShiftService.swift
// "Move All Forward 1 Day" for the merged Lessons & Work calendar.
//
// The whole plan slides one school day later — presentations *and* the work
// checks alongside them. Work used to stay put while the lessons moved, which
// pulled a day in half: the presentation landed on Tuesday and the check on the
// work it produced was still sitting on Monday, so a guide who pushed the week
// had to walk the work across day by day afterwards.
//
// Only what the guide can see moves (bug hunt 2026-10-12, #49): what the Show
// filter shows, dated today or later, and check-ins on open work. It used to
// move hidden presentations, weeks-old overdue items and finished work's
// check-ins too, with no question first and no way back; the strip now asks
// with `pending`'s counts and offers Undo from the `Receipt`.
//
// A service rather than another method on the calendar view, because the rule
// it encodes — what moves, how far, and what travels with it — is the part
// worth testing, and a `View` extension cannot be.

import CoreData
import Foundation

enum CalendarForwardShiftService {

    /// What a shift touched, so the caller knows whether there is anything to
    /// save, and what it moved, so it can be taken back.
    struct Result: Equatable {
        var presentations: Int = 0
        var checkIns: Int = 0
        /// Each moved record's day before and after. Not part of equality:
        /// two results are the same shift when they moved the same counts.
        var receipt = Receipt()

        var isEmpty: Bool { presentations == 0 && checkIns == 0 }

        static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.presentations == rhs.presentations && lhs.checkIns == rhs.checkIns
        }
    }

    /// One record's date before and after the shift.
    struct Move<Value: Equatable> {
        let objectID: NSManagedObjectID
        let before: Value
        let after: Value
    }

    /// What `undo` puts back.
    struct Receipt {
        var presentations: [Move<Date>] = []
        var checkIns: [Move<Date>] = []
        var dueDays: [Move<Date?>] = []
    }

    /// How many presentations and check-ins a shift would move now, without
    /// moving them: the confirmation's counts.
    static func pending(
        in context: NSManagedObjectContext,
        calendar: Calendar,
        kinds: CalendarKindFilter,
        from today: Date
    ) -> Result {
        let start = calendar.startOfDay(for: today)
        return Result(
            presentations: kinds.showsPresentations ? scheduledPresentations(from: start, in: context).count : 0,
            checkIns: kinds.showsWork ? movableCheckIns(from: start, in: context).checkIns.count : 0
        )
    }

    /// Moves every scheduled presentation and work check the strip shows, dated
    /// `today` or later, one school day later.
    ///
    /// `nextSchoolDay` is passed in rather than resolved here: it reads the
    /// school-day cache, which is a different concern from the shift itself and
    /// the one a test wants to pin down. Answers are memoized per start-of-day,
    /// since a classroom's plan lands on a handful of dates rather than one per
    /// record.
    ///
    /// Nothing is saved — the calendar owns the save coordinator.
    @discardableResult
    static func moveForwardOneDay(
        in context: NSManagedObjectContext,
        calendar: Calendar,
        kinds: CalendarKindFilter = .everything,
        from today: Date = Date(),
        nextSchoolDay: (Date) -> Date
    ) -> Result {
        var resolved: [Date: Date] = [:]
        func nextDay(after date: Date) -> Date {
            let key = calendar.startOfDay(for: date)
            if let cached = resolved[key] { return cached }
            let next = nextSchoolDay(key)
            resolved[key] = next
            return next
        }

        let start = calendar.startOfDay(for: today)
        var result = Result()

        if kinds.showsPresentations {
            for assignment in scheduledPresentations(from: start, in: context) {
                guard let current = assignment.scheduledFor else { continue }
                // Carry the within-day position across, or moving the week forward
                // would flatten every day's order to a single instant.
                let moved = preservingTimeOfDay(from: current, onto: nextDay(after: current), using: calendar)
                assignment.setScheduledFor(moved, using: calendar)
                result.receipt.presentations.append(Move(objectID: assignment.objectID, before: current, after: moved))
                result.presentations += 1
            }
        }

        guard kinds.showsWork else { return result }
        let (checkIns, works) = movableCheckIns(from: start, in: context)
        var touched = Set<UUID>()
        for checkIn in checkIns {
            guard let current = checkIn.date else { continue }
            let moved = preservingTimeOfDay(from: current, onto: nextDay(after: current), using: calendar)
            checkIn.date = moved
            result.receipt.checkIns.append(Move(objectID: checkIn.objectID, before: current, after: moved))
            result.checkIns += 1
            if let workID = checkIn.workID.asUUID { touched.insert(workID) }
        }
        // The work's due date travels with its checks — the same pairing a
        // single dragged pill keeps — and is the soonest check still waiting
        // after the move. An overdue one isn't moved, so it can be the soonest:
        // the work is never due after one of its own open checks (bug hunt
        // 2026-10-12 #49).
        for workID in touched {
            guard let work = works[workID], let due = earliestScheduledDate(of: work, in: context) else { continue }
            result.receipt.dueDays.append(Move(objectID: work.objectID, before: work.dueAt, after: due))
            work.dueAt = due
        }
        return result
    }

    /// The day of `work`'s soonest check-in still scheduled, read through the
    /// relationship and the `workID` string both.
    private static func earliestScheduledDate(of work: CDWorkModel, in context: NSManagedObjectContext) -> Date? {
        WorkDeletionService.checkIns(of: work, in: context)
            .filter { !$0.isDeleted && $0.status == .scheduled }
            .compactMap(\.date)
            .min()
    }

    /// Moves as `moveForwardOneDay` does and saves through `persist`. A
    /// failed save takes the move back and returns nil; an empty move saves
    /// nothing. The move runs in a `ContextMutationTransaction`, so a failure
    /// restores everything it changed — states and modified stamps too, which
    /// putting the days back by hand left edited — and nothing else.
    static func moveForwardOneDayAndSave(
        in context: NSManagedObjectContext,
        calendar: Calendar,
        kinds: CalendarKindFilter = .everything,
        from today: Date = Date(),
        nextSchoolDay: (Date) -> Date,
        persist: () -> Bool
    ) -> Result? {
        let transaction = ContextMutationTransaction(context: context)
        let moved = moveForwardOneDay(
            in: context, calendar: calendar, kinds: kinds, from: today, nextSchoolDay: nextSchoolDay
        )
        if moved.isEmpty || persist() {
            transaction.commit()
            return moved
        }
        transaction.rollback()
        // A row the undo put back can still read as edited with nothing
        // changed; refresh it so the context doesn't look as if it had
        // unsaved work.
        for object in context.updatedObjects where object.changedValues().isEmpty {
            context.refresh(object, mergeChanges: false)
        }
        return nil
    }

    /// Puts back what `receipt` moved, leaving any record changed since (a
    /// pill dragged again, a lesson given) as it now is. Nothing is saved.
    /// Returns how many presentations and check-ins went back.
    @discardableResult
    static func undo(_ receipt: Receipt, in context: NSManagedObjectContext, calendar: Calendar) -> Int {
        var restored = 0
        for move in receipt.presentations {
            guard let assignment = context.existing(CDLessonAssignment.self, move.objectID),
                  !assignment.isGiven, assignment.scheduledFor == move.after else { continue }
            assignment.setScheduledFor(move.before, using: calendar)
            restored += 1
        }
        for move in receipt.checkIns {
            guard let checkIn = context.existing(CDWorkCheckIn.self, move.objectID),
                  checkIn.status == .scheduled, checkIn.date == move.after else { continue }
            checkIn.date = move.before
            restored += 1
        }
        for move in receipt.dueDays {
            guard let work = context.existing(CDWorkModel.self, move.objectID), work.dueAt == move.after else {
                continue
            }
            work.dueAt = move.before
        }
        return restored
    }

    /// Moves `source`'s time-of-day onto `day`, so a record keeps its position
    /// within the day when the whole plan shifts.
    static func preservingTimeOfDay(
        from source: Date,
        onto day: Date,
        using calendar: Calendar
    ) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(
            bySettingHour: time.hour ?? UIConstants.morningHour,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? day
    }

    // MARK: - What moves

    /// Everything still waiting to be given, from `start` on. A presentation
    /// that has already happened is a record of a day, not a plan for one, and
    /// one left on an earlier day is the guide's to place, not this move's.
    private static func scheduledPresentations(
        from start: Date,
        in context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "scheduledFor >= %@ AND stateRaw != %@",
            start as NSDate,
            LessonAssignmentState.presented.rawValue
        )
        return context.safeFetch(request).filter { !$0.isGiven }
    }

    /// Every check still waiting to happen from `start` on, not only the ones
    /// in the calendar's visible window, on work that is still open, with the
    /// works they belong to.
    private static func movableCheckIns(
        from start: Date,
        in context: NSManagedObjectContext
    ) -> (checkIns: [CDWorkCheckIn], works: [UUID: CDWorkModel]) {
        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = NSPredicate(
            format: "statusRaw == %@ AND date >= %@",
            WorkCheckInStatus.scheduled.rawValue, start as NSDate
        )
        let checkIns = context.safeFetch(request)
        let works = worksByID(for: checkIns, in: context)
        let open = checkIns.filter { checkIn in
            checkIn.workID.asUUID.flatMap { works[$0] }.map { !$0.isClosed } ?? false
        }
        return (open, works)
    }

    /// The works a set of check-ins belongs to, in one fetch rather than one
    /// per check-in.
    private static func worksByID(
        for checkIns: [CDWorkCheckIn],
        in context: NSManagedObjectContext
    ) -> [UUID: CDWorkModel] {
        let ids = Set(checkIns.compactMap { $0.workID.asUUID })
        guard !ids.isEmpty else { return [:] }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id IN %@", ids as NSSet)
        return Dictionary(
            context.safeFetch(request).compactMap { work in work.id.map { ($0, work) } },
            // CloudKit sync can leave duplicate rows sharing an id; first wins,
            // matching every other lookup table in the app.
            uniquingKeysWith: { first, _ in first }
        )
    }
}
