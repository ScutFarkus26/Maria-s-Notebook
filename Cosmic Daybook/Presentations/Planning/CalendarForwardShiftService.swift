// CalendarForwardShiftService.swift
// "Move All Forward 1 Day" for the merged Lessons & Work calendar.
//
// The whole plan slides one school day later — presentations *and* the work
// checks alongside them. Work used to stay put while the lessons moved, which
// pulled a day in half: the presentation landed on Tuesday and the check on the
// work it produced was still sitting on Monday, so a guide who pushed the week
// had to walk the work across day by day afterwards.
//
// What moves (2026-10-13, reversing part of bug hunt 2026-10-12 #49):
// presentations the Show filter shows, dated today or later; and every open
// work check, whatever the Show filter shows. A check left on an earlier day
// comes to today, and one from today on moves one school day later. #49 had
// stopped moving weeks-old checks because the move used to happen with no
// question first and no way back; the strip now asks with `pending`'s counts
// and offers Undo from the `Receipt`, so Danny chose to have them come along.
// A presentation left on an earlier day still stays: it is the guide's to
// place.
//
// Every child's linked copy moves with its group (`WorkCheckInService`'s
// sibling move, which update_work's `move_check_in_from` shares), and a work
// never ends up with two checks on one day: a check that would land on a day
// its work already has one folds into that one (it is marked skipped, and
// Undo brings it back).
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
        /// Work checks moved, folded ones included.
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
        /// Checks that would have landed on a day their work already had
        /// one, marked skipped where they were.
        var folded: [NSManagedObjectID] = []
        var dueDays: [Move<Date?>] = []
    }

    /// How many presentations and check-ins a shift would move now, without
    /// moving them: the confirmation's counts. Folded checks count, since
    /// each is a check the move takes off its day.
    static func pending(
        in context: NSManagedObjectContext,
        calendar: Calendar,
        kinds: CalendarKindFilter,
        from today: Date
    ) -> Result {
        let start = calendar.startOfDay(for: today)
        return Result(
            presentations: kinds.showsPresentations ? scheduledPresentations(from: start, in: context).count : 0,
            // Every open linked copy's scheduled check is in this set too, so
            // the sibling moves add none: each is moved or folded once.
            checkIns: movableCheckIns(in: context).count
        )
    }

    /// Moves every scheduled presentation the strip shows, dated `today` or
    /// later, one school day later, and every open work check: an overdue one
    /// to today, and one from today on a school day later.
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
        let start = calendar.startOfDay(for: today)
        /// The day a record on `date` moves to: today for an overdue one, the
        /// next school day for one from today on.
        func landing(for date: Date) -> Date {
            let key = calendar.startOfDay(for: date)
            if key < start { return start }
            if let cached = resolved[key] { return cached }
            let next = calendar.startOfDay(for: nextSchoolDay(key))
            resolved[key] = next
            return next
        }

        var result = Result()

        if kinds.showsPresentations {
            for assignment in scheduledPresentations(from: start, in: context) {
                guard let current = assignment.scheduledFor else { continue }
                // Carry the within-day position across, or moving the week forward
                // would flatten every day's order to a single instant.
                let moved = preservingTimeOfDay(from: current, onto: landing(for: current), using: calendar)
                assignment.setScheduledFor(moved, using: calendar)
                result.receipt.presentations.append(Move(objectID: assignment.objectID, before: current, after: moved))
                result.presentations += 1
            }
        }

        var shift = CheckInShift(context: context)
        // Latest first: a work's later check leaves its day before an earlier
        // one lands there, so only a real clash folds.
        for checkIn in movableCheckIns(in: context).sorted(by: isLater) {
            guard let current = checkIn.date, let work = checkIn.resolvedWork(in: context) else { continue }
            shift.place(checkIn, of: work, from: current, to: landing(for: current), calendar: calendar)
        }
        result.checkIns = shift.receipt.checkIns.count + shift.receipt.folded.count
        result.receipt.checkIns = shift.receipt.checkIns
        result.receipt.folded = shift.receipt.folded

        // The work's due date travels with its checks — the same pairing a
        // single dragged pill keeps — and is the soonest check still waiting
        // after the move.
        for work in shift.touched.values {
            guard let due = earliestScheduledDate(of: work, in: context), due != work.dueAt else { continue }
            result.receipt.dueDays.append(Move(objectID: work.objectID, before: work.dueAt, after: due))
            work.dueAt = due
        }
        return result
    }

    /// The day of `work`'s soonest check-in still scheduled, read through the
    /// relationship and the `workID` string both.
    static func earliestScheduledDate(of work: CDWorkModel, in context: NSManagedObjectContext) -> Date? {
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
        refreshUnchanged(in: context)
        return nil
    }

    /// A row a rollback put back can still read as edited with nothing
    /// changed; refresh it so the context doesn't look as if it had unsaved
    /// work.
    static func refreshUnchanged(in context: NSManagedObjectContext) {
        for object in context.updatedObjects where object.changedValues().isEmpty {
            context.refresh(object, mergeChanges: false)
        }
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
        for objectID in receipt.folded {
            guard let checkIn = context.existing(CDWorkCheckIn.self, objectID), checkIn.status == .skipped else {
                continue
            }
            checkIn.status = .scheduled
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

    // MARK: - Moving the checks

    /// The check-ins one shift has placed, so none moves twice, and the works
    /// they belong to, whose due dates follow.
    private struct CheckInShift {
        let service: WorkCheckInService
        var receipt = Receipt()
        var placed = Set<NSManagedObjectID>()
        var touched: [NSManagedObjectID: CDWorkModel] = [:]
        /// Each work's linked copies, resolved once per group.
        private var siblings: [NSManagedObjectID: [CDWorkModel]] = [:]

        init(context: NSManagedObjectContext) {
            service = WorkCheckInService(context: context)
        }

        /// Moves `checkIn` from `current` onto `day`, or folds it into the
        /// check its work already has there, then brings its linked copies'
        /// checks on the same day along.
        mutating func place(
            _ checkIn: CDWorkCheckIn, of work: CDWorkModel, from current: Date, to day: Date, calendar: Calendar
        ) {
            guard placed.insert(checkIn.objectID).inserted else { return }
            touched[work.objectID] = work
            if service.blockingCheckIn(of: work, on: day, excluding: checkIn) != nil {
                fold(checkIn)
            } else {
                let moved = preservingTimeOfDay(from: current, onto: day, using: calendar)
                checkIn.date = moved
                receipt.checkIns.append(Move(objectID: checkIn.objectID, before: current, after: moved))
            }
            let fromDay = calendar.startOfDay(for: current)
            for sibling in linkedCopies(of: work) where !sibling.isClosed {
                moveSibling(sibling, from: fromDay, to: day)
            }
        }

        /// A copy whose check on the day this shift has already placed has
        /// nothing scheduled left there, so it is never moved twice.
        private mutating func moveSibling(_ sibling: CDWorkModel, from fromDay: Date, to day: Date) {
            switch service.moveSiblingCheckIn(of: sibling, from: fromDay, to: day) {
            case .moved(let checkIn):
                guard placed.insert(checkIn.objectID).inserted, let after = checkIn.date else { return }
                touched[sibling.objectID] = sibling
                // Only the day changed, so the time it had is the time it has.
                let before = preservingTimeOfDay(from: after, onto: fromDay, using: AppCalendar.shared)
                receipt.checkIns.append(Move(objectID: checkIn.objectID, before: before, after: after))
            case .blocked(let checkIn, _):
                guard placed.insert(checkIn.objectID).inserted else { return }
                touched[sibling.objectID] = sibling
                fold(checkIn)
            case .childHasLeft, .settled, .noneOnDay:
                break
            }
        }

        /// Two checks for one work on one day become one: the one already
        /// there stands, and this one is marked skipped where it was, notes
        /// and all.
        private mutating func fold(_ checkIn: CDWorkCheckIn) {
            checkIn.status = .skipped
            receipt.folded.append(checkIn.objectID)
        }

        private mutating func linkedCopies(of work: CDWorkModel) -> [CDWorkModel] {
            if let cached = siblings[work.objectID] { return cached }
            let group = WorkGrouping.group(containing: work, in: service.context)
            for member in group.members {
                siblings[member.objectID] = group.members.filter { $0 !== member }
            }
            return group.siblings
        }
    }

    private static func isLater(_ lhs: CDWorkCheckIn, _ rhs: CDWorkCheckIn) -> Bool {
        let lhsDate = lhs.date ?? .distantPast
        let rhsDate = rhs.date ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
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

    /// Every check still waiting to happen, on any day, on work that is still
    /// open — read through the relationship or the `workID` string, whichever
    /// the check-in has.
    static func movableCheckIns(in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = NSPredicate(
            format: "statusRaw == %@ AND date != nil", WorkCheckInStatus.scheduled.rawValue
        )
        return context.safeFetch(request).filter { checkIn in
            !checkIn.isDeleted && checkIn.resolvedWork(in: context).map { !$0.isClosed } == true
        }
    }
}
