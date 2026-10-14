// CalendarClearAllService.swift
// "Clear All to Inbox" for the merged Lessons & Work calendar.
//
// Every planned presentation not yet given goes back to the Inbox, and every
// open work check comes off the calendar with it, every child's linked copy
// included, so the work goes back to To Schedule (2026-10-13). It used to
// clear presentations alone, leaving their work checks on days that no longer
// held the lessons, and saved at once with no way back; it now asks with
// `pending`'s counts and offers Undo from the `Receipt`, as Move All Forward
// does.
//
// A check-in carrying a note stays where it is: deleting it would lose the
// note. Any other open one is deleted, which is what "not scheduled" means
// for work (`LessonsAndWorkTriage.bucket`), and its work's due date becomes
// its soonest check still scheduled, or none.

import CoreData
import Foundation

enum CalendarClearAllService {

    /// What a clear did, or would do.
    struct Result: Equatable {
        var presentations: Int = 0
        /// Work checks taken off the calendar.
        var checkIns: Int = 0
        /// Work checks left on their days because each carries a note.
        var keptForNotes: Int = 0
        /// Not part of equality: two results are the same clear when they
        /// cleared the same counts.
        var receipt = Receipt()

        var isEmpty: Bool { presentations == 0 && checkIns == 0 }

        static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.presentations == rhs.presentations && lhs.checkIns == rhs.checkIns
                && lhs.keptForNotes == rhs.keptForNotes
        }
    }

    /// What `undo` puts back.
    struct Receipt {
        /// Each cleared presentation and the time it was planned for.
        var presentations: [(objectID: NSManagedObjectID, scheduledFor: Date)] = []
        var checkIns: [WorkCheckInService.RemovedCheckIn] = []
        var dueDays: [CalendarForwardShiftService.Move<Date?>] = []
    }

    /// How many presentations and check-ins a clear would take off the
    /// calendar now, and how many it would leave for their notes, without
    /// touching any: the confirmation's counts.
    static func pending(in context: NSManagedObjectContext) -> Result {
        let checkIns = CalendarForwardShiftService.movableCheckIns(in: context)
        let kept = checkIns.filter(WorkCheckInService.hasNote).count
        return Result(
            presentations: scheduledPresentations(in: context).count,
            checkIns: checkIns.count - kept,
            keptForNotes: kept
        )
    }

    /// Unschedules every planned presentation and takes every open work
    /// check off the calendar, linked copies included (each open copy's
    /// checks are open checks themselves). Nothing is saved.
    @discardableResult
    static func clearAll(in context: NSManagedObjectContext) -> Result {
        var result = Result()
        for assignment in scheduledPresentations(in: context) {
            guard let before = assignment.scheduledFor else { continue }
            assignment.unschedule()
            result.receipt.presentations.append((assignment.objectID, before))
            result.presentations += 1
        }

        let service = WorkCheckInService(context: context)
        var works: [NSManagedObjectID: CDWorkModel] = [:]
        for checkIn in CalendarForwardShiftService.movableCheckIns(in: context) {
            let work = checkIn.resolvedWork(in: context)
            guard let removed = service.unschedule(checkIn) else {
                result.keptForNotes += 1
                continue
            }
            // Only a work that lost a check has its due date reset; one whose
            // only check kept its note stays as it was.
            if let work { works[work.objectID] = work }
            result.receipt.checkIns.append(removed)
            result.checkIns += 1
        }
        context.processPendingChanges()

        // The due date follows what is left, as it does when the plan moves:
        // a note's check still on the calendar, or nothing, which is To
        // Schedule.
        for work in works.values {
            let due = CalendarForwardShiftService.earliestScheduledDate(of: work, in: context)
            guard due != work.dueAt else { continue }
            result.receipt.dueDays.append(.init(objectID: work.objectID, before: work.dueAt, after: due))
            work.dueAt = due
        }
        return result
    }

    /// Clears as `clearAll` does and saves through `persist`. A failed save
    /// takes the whole clear back and returns nil; an empty clear saves
    /// nothing.
    static func clearAllAndSave(in context: NSManagedObjectContext, persist: () -> Bool) -> Result? {
        let transaction = ContextMutationTransaction(context: context)
        let cleared = clearAll(in: context)
        if cleared.isEmpty || persist() {
            transaction.commit()
            return cleared
        }
        transaction.rollback()
        CalendarForwardShiftService.refreshUnchanged(in: context)
        return nil
    }

    /// Puts back what `receipt` cleared, leaving anything planned again since
    /// as it now is. Nothing is saved. Returns how many presentations and
    /// check-ins went back.
    @discardableResult
    static func undo(_ receipt: Receipt, in context: NSManagedObjectContext, calendar: Calendar) -> Int {
        var restored = 0
        for cleared in receipt.presentations {
            guard let assignment = context.existing(CDLessonAssignment.self, cleared.objectID),
                  !assignment.isGiven, assignment.scheduledFor == nil else { continue }
            assignment.setScheduledFor(cleared.scheduledFor, using: calendar)
            restored += 1
        }
        let service = WorkCheckInService(context: context)
        for removed in receipt.checkIns where service.restore(removed) != nil {
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

    /// Every presentation planned for a day and not yet given, on any day.
    private static func scheduledPresentations(in context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "scheduledFor != nil AND stateRaw != %@", LessonAssignmentState.presented.rawValue
        )
        return context.safeFetch(request).filter { !$0.isGiven }
    }
}
