// TimetableService+Blocks.swift
// Adding, editing and deleting blocks: on one or more weekdays, one-offs, the
// three edit scopes, copying a day to other weekdays, and replacing a lane's
// week from a day on (MCP's set_timetable).

import CoreData
import Foundation

extension TimetableService {

    /// One weekly block of a lane's week, for `replaceWeek`.
    struct WeeklyBlock: Sendable, Equatable {
        var weekday: Weekday
        var values: TimetableBlockValues
    }

    /// What an edit sets on a block, field by field; a field left nil keeps
    /// what is there. The block sheet sends only what Danny changed, so a
    /// field it doesn't show (a room's children), one he left alone (an odd
    /// length, the children's order) and a change made for one day only keep
    /// their stored values.
    struct BlockEdit: Sendable, Equatable {
        var startMinute: Int?
        var lengthMinutes: Int?
        var title: String?
        var note: String?
        var teacher: Teacher?
        var studentIDs: [String]?

        /// Nothing set: saving it would change nothing.
        var isEmpty: Bool { self == BlockEdit() }

        /// `values` with what this edit sets.
        func applied(to values: TimetableBlockValues) -> TimetableBlockValues {
            var result = values
            if let startMinute { result.startMinute = startMinute }
            if let lengthMinutes { result.lengthMinutes = lengthMinutes }
            if let title { result.title = title }
            if let note { result.note = note }
            if let teacher {
                result.teacherLaneID = teacher.laneID
                result.teacherName = teacher.name
            }
            if let studentIDs { result.studentIDs = studentIDs }
            return result
        }
    }

    // MARK: - Adding

    /// Adds a weekly block to `lane` on each of `weekdays`, one block per day.
    /// `day`, when given, is the first day it applies (earlier weeks don't
    /// show it); nil, it applies to every week.
    @discardableResult
    static func addBlock(
        _ values: TimetableBlockValues,
        to lane: CDTimetableLane,
        on weekdays: [Weekday],
        from day: Date? = nil,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) -> [CDTimetableBlock] {
        guard let laneID = lane.id?.uuidString else { return [] }
        var seen = Set<String>()
        return weekdays.filter { seen.insert($0.rawValue).inserted }.map { weekday in
            insertBlock(
                values, laneID: laneID, weekday: weekday, validFrom: day.map(calendar.startOfDay(for:)),
                in: context, now: now
            )
        }
    }

    /// Adds a one-off to `lane` on `day` (Add to This Day): an assembly, a
    /// trip, an early dismissal.
    @discardableResult
    static func addOneOff(
        _ values: TimetableBlockValues,
        to lane: CDTimetableLane,
        on day: Date,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) -> CDTimetableBlock? {
        guard let laneID = lane.id?.uuidString else { return nil }
        return insertBlock(values, laneID: laneID, onDay: calendar.startOfDay(for: day), in: context, now: now)
    }

    // MARK: - Editing

    /// Edits `block` as seen on `day` to `values` in full (see the edit below).
    @discardableResult
    static func edit(
        _ block: CDTimetableBlock,
        to values: TimetableBlockValues,
        scope: EditScope,
        on day: Date,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) -> CDTimetableBlock {
        edit(
            block, applying: BlockEdit(setting: values), scope: scope, on: day, in: context, now: now,
            calendar: calendar
        )
    }

    /// Edits `block` as seen on `day`, changing only what `edit` sets: every
    /// other field keeps the block's own value, and on `day` what that day's
    /// own change has, so a change made for one day stays on its day. Returns
    /// the block that shows the edit from then on: the copy for This Day and
    /// After on a block that began before `day`, otherwise `block` itself.
    ///
    /// - Only This Day records a "changed" change for `day`: the day's values
    ///   with the edit (one already there is updated; values equal to the
    ///   block's remove it).
    /// - This Day and After ends `block` the day before and starts a copy on
    ///   `day`, the block's own values with the edit; later days' changes
    ///   move to the copy, and `day` keeps its own change with the edit. A
    ///   block that begins on or after `day` is edited in place, and an edit
    ///   that leaves the weekly values as they were changes `day` alone.
    /// - Every week edits the block itself, and `day`'s own change with it.
    ///
    /// A one-off is edited in place whatever the scope.
    @discardableResult
    static func edit(
        _ block: CDTimetableBlock,
        applying edit: BlockEdit,
        scope: EditScope,
        on day: Date,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) -> CDTimetableBlock {
        let day = calendar.startOfDay(for: day)
        if block.isOneOff {
            touch(block, with: edit.applied(to: block.values), now: now)
            return block
        }
        let own = changedValues(of: block, on: day, in: context, calendar: calendar)
        let dayValues = edit.applied(to: own ?? block.values)
        let weekly = edit.applied(to: block.values)
        switch scope {
        case .everyWeek:
            touch(block, with: weekly, now: now)
            if own != nil {
                setDayValues(dayValues, for: block, on: day, in: context, now: now, calendar: calendar)
            }
            return block
        case .onlyThisDay:
            setDayValues(dayValues, for: block, on: day, in: context, now: now, calendar: calendar)
            return block
        case .thisDayAndAfter:
            // A block that ended before the day has nothing on or after it to edit.
            guard isRunning(block, onOrAfter: day, calendar: calendar) else { return block }
            guard weekly != block.values else {
                setDayValues(dayValues, for: block, on: day, in: context, now: now, calendar: calendar)
                return block
            }
            // The day keeps what it showed with the edit, unless that is every week's now.
            if dayValues == weekly {
                undoChanges(to: block, on: day, in: context, calendar: calendar)
            } else {
                upsertChange(
                    .changed, values: dayValues, for: block, on: day, in: context, now: now, calendar: calendar
                )
            }
            return split(block, from: day, values: weekly, in: context, now: now, calendar: calendar)
        }
    }

    /// Deletes `block` as seen on `day`.
    ///
    /// - Only This Day cancels it that day.
    /// - This Day and After ends it the day before (a block that begins on or
    ///   after `day` is deleted outright, with its changes).
    /// - Every week ends it from today, so the weeks already past still show it.
    ///
    /// A one-off is deleted, with its changes, whatever the scope.
    static func delete(
        _ block: CDTimetableBlock,
        scope: EditScope,
        on day: Date,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) {
        if block.isOneOff {
            remove(block, in: context, calendar: calendar)
            return
        }
        switch scope {
        case .onlyThisDay:
            cancel(block, on: day, in: context, now: now, calendar: calendar)
        case .thisDayAndAfter:
            end(block, before: calendar.startOfDay(for: day), in: context, now: now, calendar: calendar)
        case .everyWeek:
            end(block, before: calendar.startOfDay(for: now), in: context, now: now, calendar: calendar)
        }
    }

    // MARK: - Copying and replacing

    /// Copies `lane`'s weekly blocks on `source` to each of `targets` (Copy
    /// Day To…), adding to what's there. A target that already has a block at
    /// the same time, length and title isn't given a second. `day`, when
    /// given, is the first day the copies apply; nil, they keep the source
    /// blocks' days. Only blocks still running on `day` (or today) are copied.
    @discardableResult
    static func copyDay(
        _ source: Weekday,
        of lane: CDTimetableLane,
        to targets: [Weekday],
        from day: Date? = nil,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) -> [CDTimetableBlock] {
        let reference = calendar.startOfDay(for: day ?? now)
        let running = blocks(of: lane, in: context).filter {
            !$0.isOneOff && isRunning($0, onOrAfter: reference, calendar: calendar)
        }
        let sources = running.filter { $0.weekday == source }
        var copies: [CDTimetableBlock] = []
        var seen = Set<String>()
        for target in targets where target != source && seen.insert(target.rawValue).inserted {
            var there = running.filter { $0.weekday == target }.map(\.values)
            for block in sources where !there.contains(where: { sameSlot($0, block.values) }) {
                let copy = insertBlock(
                    block.values, laneID: block.laneID, weekday: target,
                    validFrom: day.map(calendar.startOfDay(for:)) ?? block.validFrom, validUntil: block.validUntil,
                    in: context, now: now
                )
                there.append(copy.values)
                copies.append(copy)
            }
        }
        return copies
    }

    /// Replaces `lane`'s weekly blocks from `day` on with `week`, This Day and
    /// After style: every weekly block still running ends the day before (or
    /// goes, if it begins on or after `day`), and the new blocks start on
    /// `day`. One-offs stay. MCP's set_timetable writes through here.
    @discardableResult
    static func replaceWeek(
        of lane: CDTimetableLane,
        with week: [WeeklyBlock],
        from day: Date,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) -> [CDTimetableBlock] {
        guard let laneID = lane.id?.uuidString else { return [] }
        let day = calendar.startOfDay(for: day)
        for block in blocks(of: lane, in: context) where !block.isOneOff {
            end(block, before: day, in: context, now: now, calendar: calendar)
        }
        return week.map { entry in
            insertBlock(entry.values, laneID: laneID, weekday: entry.weekday, validFrom: day, in: context, now: now)
        }
    }

    // MARK: - Steps

    static func insertBlock(
        _ values: TimetableBlockValues,
        laneID: String,
        weekday: Weekday? = nil,
        onDay: Date? = nil,
        validFrom: Date? = nil,
        validUntil: Date? = nil,
        in context: NSManagedObjectContext,
        now: Date
    ) -> CDTimetableBlock {
        let block = CDTimetableBlock(context: context)
        assignToGuideStore(block, in: context)
        block.laneID = laneID
        block.weekday = weekday
        block.onDay = onDay
        block.apply(values)
        block.validFrom = validFrom
        block.validUntil = validUntil
        block.createdAt = now
        block.modifiedAt = now
        return block
    }

    private static func touch(_ block: CDTimetableBlock, with values: TimetableBlockValues, now: Date) {
        if block.apply(values) { block.modifiedAt = now }
    }

    /// This Day and After: see `edit`, which has already set the day's own
    /// change, so it moves to the copy with the later days'.
    private static func split( // swiftlint:disable:this function_parameter_count
        _ block: CDTimetableBlock,
        from day: Date,
        values: TimetableBlockValues,
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) -> CDTimetableBlock {
        // A block that ended before the day has nothing on or after it to edit.
        guard isRunning(block, onOrAfter: day, calendar: calendar) else { return block }
        let later = changes(of: block, from: day, in: context, calendar: calendar)
        // A change with no day is no day's: it goes.
        for change in later where change.day == nil {
            context.delete(change)
        }
        if let from = block.validFrom, calendar.startOfDay(for: from) >= day {
            touch(block, with: values, now: now)
            return block
        }
        let copy = insertBlock(
            values, laneID: block.laneID, weekday: block.weekday, validFrom: day, validUntil: block.validUntil,
            in: context, now: now
        )
        block.validUntil = dayBefore(day, calendar: calendar)
        block.modifiedAt = now
        let copyID = copy.id?.uuidString
        for change in later where !change.isDeleted {
            change.blockID = copyID
            change.modifiedAt = now
        }
        return copy
    }

    /// Ends `block` before `day`: the day before becomes its last, and its
    /// changes from `day` on go. A block that begins on or after `day` goes
    /// with all its changes; one already ended stays as it is.
    static func end(
        _ block: CDTimetableBlock,
        before day: Date,
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) {
        guard isRunning(block, onOrAfter: day, calendar: calendar) else { return }
        if let from = block.validFrom, calendar.startOfDay(for: from) >= day {
            remove(block, in: context, calendar: calendar)
            return
        }
        block.validUntil = dayBefore(day, calendar: calendar)
        block.modifiedAt = now
        for change in changes(of: block, from: day, in: context, calendar: calendar) {
            context.delete(change)
        }
    }

    /// Deletes `block` and every change made to it.
    static func remove(_ block: CDTimetableBlock, in context: NSManagedObjectContext, calendar: Calendar) {
        for change in changes(of: block, from: .distantPast, in: context, calendar: calendar) {
            context.delete(change)
        }
        context.delete(block)
    }

    /// Whether a weekly block applies on `day` or any day after.
    static func isRunning(_ block: CDTimetableBlock, onOrAfter day: Date, calendar: Calendar) -> Bool {
        guard let until = block.validUntil else { return true }
        return calendar.startOfDay(for: until) >= calendar.startOfDay(for: day)
    }

    /// The same time, length and title (ignoring case and spaces).
    private static func sameSlot(_ lhs: TimetableBlockValues, _ rhs: TimetableBlockValues) -> Bool {
        lhs.startMinute == rhs.startMinute && lhs.lengthMinutes == rhs.lengthMinutes
            && lhs.title.foldedKey() == rhs.title.foldedKey()
    }
}

extension TimetableService.BlockEdit {
    /// Who teaches: the person lane and the typed name are set together.
    struct Teacher: Sendable, Equatable {
        var laneID: UUID?
        var name: String
    }

    /// Every field: the block becomes `values`.
    init(setting values: TimetableBlockValues) {
        self.init(
            startMinute: values.startMinute, lengthMinutes: values.lengthMinutes, title: values.title,
            note: values.note, teacher: Teacher(laneID: values.teacherLaneID, name: values.teacherName),
            studentIDs: values.studentIDs
        )
    }
}
