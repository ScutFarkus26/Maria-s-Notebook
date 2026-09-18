// DayBalanceService.swift
// The store side of the AM/PM balance gesture: read a day out of Core Data,
// hand it to `DayHalfBalancer`, write the answer back, and say in one sentence
// what happened.
//
// Both callers come through here — the button on a single day column, and the
// week-wide item in the calendar's Actions menu — so the rule for what counts
// as a clash, the wording that reports one, and the Undo that takes it back are
// each written once.

import Foundation
import CoreData

enum DayBalanceService {
    /// What one day's rearrangement did, and what it could not do.
    struct Result {
        let movedToMorning: Int
        let movedToAfternoon: Int
        let unresolvedStudentIDs: Set<UUID>
        /// Every `scheduledFor` this rewrite replaced, so Undo can put the day
        /// back exactly. The balancer renumbers the whole day, so restoring
        /// only the cards that changed halves would leave the ones around them
        /// carrying new offsets.
        let previousTimes: [UUID: Date]

        var movedCount: Int { movedToMorning + movedToAfternoon }
        var isClean: Bool { unresolvedStudentIDs.isEmpty }
    }

    // MARK: - Reading a day

    /// A day's presentations in the form the balancer takes them.
    ///
    /// A row with no `scheduledFor` reads as a morning, the same half every
    /// other part of the planner gives it.
    static func bookings(
        for assignments: [CDLessonAssignment],
        using calendar: Calendar
    ) -> [DayHalfBalancer.Booking] {
        assignments.compactMap { assignment in
            guard let id = assignment.id else { return nil }
            let period = assignment.scheduledFor
                .map { DayPeriod(scheduledFor: $0, using: calendar) } ?? .morning
            return DayHalfBalancer.Booking(
                id: id,
                period: period,
                studentIDs: Set(assignment.studentUUIDs)
            )
        }
    }

    /// Children called twice in the same half, by the half they clash in.
    static func clashes(
        for assignments: [CDLessonAssignment],
        using calendar: Calendar
    ) -> [DayPeriod: Set<UUID>] {
        DayHalfBalancer.clashes(in: bookings(for: assignments, using: calendar))
    }

    // MARK: - Rearranging

    /// Rearranges one day. `assignments` is that day's pending presentations in
    /// draw order, and nothing else on the calendar is touched — the balance is
    /// within a day, so widening the write would only put days at risk that had
    /// nothing wrong with them.
    ///
    /// Returns nil when the day holds nothing to arrange.
    static func balance(
        day: Date,
        assignments: [CDLessonAssignment],
        calendar: Calendar,
        context: NSManagedObjectContext
    ) -> Result? {
        let byID = Dictionary(
            assignments.compactMap { item in item.id.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )
        guard !byID.isEmpty else { return nil }

        let outcome = DayHalfBalancer.balanced(bookings(for: assignments, using: calendar))
        guard outcome.movedCount > 0 else {
            // Either the day was already clean or two halves have no answer for
            // it. Say so, rather than renumbering a day to no effect.
            return Result(
                movedToMorning: 0,
                movedToAfternoon: 0,
                unresolvedStudentIDs: outcome.unresolvedStudentIDs,
                previousTimes: [:]
            )
        }

        var previous: [UUID: Date] = [:]
        for (id, assignment) in byID {
            if let when = assignment.scheduledFor { previous[id] = when }
        }

        let times = DayHalfPlanner.times(
            for: outcome.placements,
            on: day,
            using: calendar,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )
        for (id, time) in times {
            byID[id]?.setScheduledFor(time, using: AppCalendar.shared)
        }
        context.safeSave()

        return Result(
            movedToMorning: outcome.movedToMorning.count,
            movedToAfternoon: outcome.movedToAfternoon.count,
            unresolvedStudentIDs: outcome.unresolvedStudentIDs,
            previousTimes: previous
        )
    }

    /// Puts balanced days back the way they were.
    static func restore(_ times: [UUID: Date], in context: NSManagedObjectContext) {
        guard !times.isEmpty else { return }
        let request = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
        request.predicate = NSPredicate(format: "id IN %@", Array(times.keys))
        for assignment in context.safeFetch(request) {
            if let id = assignment.id, let when = times[id] {
                assignment.setScheduledFor(when, using: AppCalendar.shared)
            }
        }
        context.safeSave()
    }

    // MARK: - Saying what happened

    /// One line for the toast: what moved, and who is still doubled up.
    static func summary(for result: Result, context: NSManagedObjectContext) -> String {
        [
            movedSentence(result),
            stillDoubledSentence(result.unresolvedStudentIDs, context: context)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    /// "Tzofia G. is still doubled up." — nil when nobody is.
    ///
    /// Named rather than counted while it can be: the guide's next move is to
    /// go and look at that child's day, and a number sends him hunting.
    static func stillDoubledSentence(_ ids: Set<UUID>, context: NSManagedObjectContext) -> String? {
        guard !ids.isEmpty else { return nil }
        let names = studentNames(ids, context: context)
        guard !names.isEmpty else {
            let who = ids.count == 1 ? "One child is" : "\(ids.count) children are"
            return "\(who) still doubled up."
        }
        switch names.count {
        case 1: return "\(names[0]) is still doubled up."
        case 2: return "\(names[0]) and \(names[1]) are still doubled up."
        default: return "\(names[0]) and \(names.count - 1) others are still doubled up."
        }
    }

    private static func movedSentence(_ result: Result) -> String? {
        switch (result.movedToMorning, result.movedToAfternoon) {
        case (0, 0):
            return result.isClean ? "Nothing to rearrange." : "Two halves can't separate this day."
        case (0, let afternoon):
            return "Moved \(lessons(afternoon)) to the afternoon."
        case (let morning, 0):
            return "Moved \(lessons(morning)) to the morning."
        case (let morning, let afternoon):
            return "Rearranged \(lessons(morning + afternoon))."
        }
    }

    private static func lessons(_ count: Int) -> String {
        count == 1 ? "1 lesson" : "\(count) lessons"
    }

    private static func studentNames(_ ids: Set<UUID>, context: NSManagedObjectContext) -> [String] {
        let request = NSFetchRequest<CDStudent>(entityName: "Student")
        request.predicate = NSPredicate(format: "id IN %@", Array(ids))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)]
        return context.safeFetch(request).map(StudentFormatter.displayName(for:))
    }
}
