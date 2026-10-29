// TimetableService+Days.swift
// One day's changes: a block's values for one day, cancelling it that day,
// Out Today and back in, and undoing a day's change.

import CoreData
import Foundation

extension TimetableService {

    // MARK: - Reading

    /// `block`'s changes on `day` and after (`.distantPast` for all of them).
    static func changes(
        of block: CDTimetableBlock,
        from day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> [CDTimetableChange] {
        guard let id = block.id?.uuidString else { return [] }
        let request = CDFetchRequest(CDTimetableChange.self)
        let start = day == .distantPast ? day : calendar.startOfDay(for: day)
        request.predicate = NSPredicate(format: "blockID ==[c] %@ AND (day == nil OR day >= %@)", id, start as NSDate)
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    /// `block`'s changes on `day`: one, unless two devices each made one.
    static func changes(
        of block: CDTimetableBlock,
        on day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> [CDTimetableChange] {
        guard let id = block.id?.uuidString else { return [] }
        return changes(on: day, matching: NSPredicate(format: "blockID ==[c] %@", id), in: context, calendar: calendar)
    }

    /// What `block` shows on `day` by that day's own change: the newest
    /// change's values when it is a "changed" one (the newest wins, as
    /// `ScheduleDayResolver` reads it). Nil with no change, or a cancel.
    static func changedValues(
        of block: CDTimetableBlock,
        on day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> TimetableBlockValues? {
        let newest = changes(of: block, on: day, in: context, calendar: calendar).max { lhs, rhs in
            let left = lhs.modifiedAt ?? .distantPast
            let right = rhs.modifiedAt ?? .distantPast
            if left != right { return left < right }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
        return newest?.kind == .changed ? newest?.values : nil
    }

    /// Whether `lane`'s person is out on `day`.
    static func isOut(
        _ lane: CDTimetableLane,
        on day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> Bool {
        !outChanges(of: lane, on: day, in: context, calendar: calendar).isEmpty
    }

    // MARK: - Changing a day

    /// `block` shows `values` on `day` only (Only This Day). A change already
    /// there is updated; values equal to the block's own take it away.
    static func setDayValues(
        _ values: TimetableBlockValues,
        for block: CDTimetableBlock,
        on day: Date,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) {
        if values == block.values {
            undoChanges(to: block, on: day, in: context, calendar: calendar)
            return
        }
        upsertChange(.changed, values: values, for: block, on: day, in: context, now: now, calendar: calendar)
    }

    /// Cancels `block` on `day` only. A one-off is deleted instead.
    static func cancel(
        _ block: CDTimetableBlock,
        on day: Date,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) {
        if block.isOneOff {
            remove(block, in: context, calendar: calendar)
            return
        }
        upsertChange(.cancelled, values: block.values, for: block, on: day, in: context, now: now, calendar: calendar)
    }

    /// Out Today (`isOut`) on a person lane, or back in: out cancels that
    /// person's blocks for the day and shows their turns in a room as "Out".
    static func setOut(
        _ lane: CDTimetableLane,
        _ isOut: Bool,
        on day: Date,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) {
        let existing = outChanges(of: lane, on: day, in: context, calendar: calendar)
        if !isOut {
            for change in existing { context.delete(change) }
            return
        }
        guard existing.isEmpty, lane.kind == .person, let laneID = lane.id?.uuidString else { return }
        let change = CDTimetableChange(context: context)
        assignToGuideStore(change, in: context)
        change.kind = .out
        change.laneID = laneID
        change.day = calendar.startOfDay(for: day)
        change.createdAt = now
        change.modifiedAt = now
    }

    /// Takes away `block`'s change on `day`: it shows as every week again.
    static func undoChanges(
        to block: CDTimetableBlock,
        on day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) {
        for change in changes(of: block, on: day, in: context, calendar: calendar) {
            context.delete(change)
        }
    }

    /// Takes away every change on `day`, people out included. One-offs stay:
    /// they're deleted as blocks.
    static func undoAllChanges(
        on day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) {
        for change in changes(on: day, matching: nil, in: context, calendar: calendar) {
            context.delete(change)
        }
    }

    // MARK: - Steps

    /// Sets `block`'s change on `day` to `kind` with `values`. Every copy is
    /// updated (two devices may each have made one), never folded, so no
    /// device's delete can take another's out of the share; readers take the
    /// newest, and all of them now say the same.
    static func upsertChange( // swiftlint:disable:this function_parameter_count
        _ kind: TimetableChangeKind,
        values: TimetableBlockValues,
        for block: CDTimetableBlock,
        on day: Date,
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) {
        let existing = changes(of: block, on: day, in: context, calendar: calendar)
        guard !existing.isEmpty else {
            guard let blockID = block.id?.uuidString else { return }
            let change = CDTimetableChange(context: context)
            assignToGuideStore(change, in: context)
            change.kind = kind
            change.blockID = blockID
            change.day = calendar.startOfDay(for: day)
            change.values = values
            change.createdAt = now
            change.modifiedAt = now
            return
        }
        for change in existing where change.kind != kind || change.values != values {
            change.kind = kind
            change.values = values
            change.modifiedAt = now
        }
    }

    private static func outChanges(
        of lane: CDTimetableLane,
        on day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar
    ) -> [CDTimetableChange] {
        guard let id = lane.id?.uuidString else { return [] }
        let predicate = NSPredicate(format: "kindRaw == %@ AND laneID ==[c] %@", TimetableChangeKind.out.rawValue, id)
        return changes(on: day, matching: predicate, in: context, calendar: calendar)
    }

    /// The changes on `day` that match `predicate`, without any deleted in the context.
    private static func changes(
        on day: Date,
        matching predicate: NSPredicate?,
        in context: NSManagedObjectContext,
        calendar: Calendar
    ) -> [CDTimetableChange] {
        let start = calendar.startOfDay(for: day)
        let dayPredicate = NSPredicate(
            format: "day >= %@ AND day < %@", start as NSDate, dayAfter(start, calendar: calendar) as NSDate
        )
        let request = CDFetchRequest(CDTimetableChange.self)
        request.predicate = predicate.map {
            NSCompoundPredicate(andPredicateWithSubpredicates: [dayPredicate, $0])
        } ?? dayPredicate
        return context.safeFetch(request).filter { !$0.isDeleted }
    }
}
