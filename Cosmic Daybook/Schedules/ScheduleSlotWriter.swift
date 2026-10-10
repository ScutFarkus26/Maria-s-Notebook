// ScheduleSlotWriter.swift
// Reading a schedule's typed times, and writing an edited schedule's slots.

import CoreData
import Foundation

/// The times a guide types into a schedule ("9:30", "1:15", "2 pm").
///
/// They were sorted as plain hour and minute numbers, so "1:15" came before
/// "9:30" (bug hunt 2026-10-10, P2 #30). AM or PM, with or without periods or
/// a space, decides the half of the day. Without one, 1 to 6 o'clock are the
/// afternoon, as they are in a school day; 7 to 12 and 24-hour times keep
/// their face value.
nonisolated enum ScheduleTime {

    /// Minutes after midnight, or nil for text that isn't a time.
    static func minutes(_ text: String) -> Int? {
        var body = text.lowercased().filter { !$0.isWhitespace && $0 != "." }
        var isAfternoon: Bool?
        for (suffix, afternoon) in [("am", false), ("pm", true), ("a", false), ("p", true)]
        where body.hasSuffix(suffix) {
            isAfternoon = afternoon
            body.removeLast(suffix.count)
            break
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let hour = Int(parts[0]) else { return nil }
        var minute = 0
        if parts.count == 2 {
            guard parts[1].count == 2, let typed = Int(parts[1]), (0..<60).contains(typed) else { return nil }
            minute = typed
        }
        if let isAfternoon {
            guard (1...12).contains(hour) else { return nil }
            return ((hour % 12) + (isAfternoon ? 12 : 0)) * 60 + minute
        }
        guard (0...23).contains(hour) else { return nil }
        return ((1...6).contains(hour) ? hour + 12 : hour) * 60 + minute
    }

    /// Earlier time first; a blank time last; text that isn't a time after
    /// the times, in text order. `.orderedSame` for two blanks or two equal
    /// times, so the caller can break the tie.
    static func order(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        let left = lhs?.trimmed() ?? ""
        let right = rhs?.trimmed() ?? ""
        switch (left.isEmpty, right.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): break
        }
        switch (minutes(left), minutes(right)) {
        case let (leftMinutes?, rightMinutes?):
            if leftMinutes == rightMinutes { return .orderedSame }
            return leftMinutes < rightMinutes ? .orderedAscending : .orderedDescending
        case (.some, nil): return .orderedAscending
        case (nil, .some): return .orderedDescending
        case (nil, nil): return left.localizedStandardCompare(right)
        }
    }
}

/// Writes an edited schedule's slots onto its stored ones in place.
///
/// Saving used to delete every slot and make new ones with new ids, so a
/// merge restore, or an edit on two devices, could leave a child on one day
/// twice (bug hunt 2026-10-10, P2 #29). Now a child still on a day keeps
/// their slot, with its new time and place; a child taken off a day loses it;
/// a child added gets a new one. Where a child is on one day twice already,
/// the slot made first stays and the others go, the same one on every device.
enum ScheduleSlotWriter {

    /// One child on one day, as the editor holds it.
    struct Entry: Equatable {
        var studentID: String
        var timeString: String
    }

    /// What one write did.
    struct Outcome: Equatable {
        var inserted = 0
        var updated = 0
        var deleted = 0
    }

    /// Each day's entries in the order they are shown and stored: by time,
    /// blank times last, ties in the order given.
    static func ordered(_ entries: [Entry]) -> [Entry] {
        ordered(entries, by: \.timeString)
    }

    /// `items` in time order (`ScheduleTime.order`), ties in the order given.
    static func ordered<Item>(_ items: [Item], by time: (Item) -> String) -> [Item] {
        items.enumerated().sorted { lhs, rhs in
            switch ScheduleTime.order(time(lhs.element), time(rhs.element)) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// The stored slots, one per child and day (the first made where there
    /// are several), with the extras listed apart.
    static func slotsByDay(
        of schedule: CDSchedule
    ) -> (kept: [Weekday: [String: CDScheduleSlot]], extras: [CDScheduleSlot]) {
        var groups: [Weekday: [String: [CDScheduleSlot]]] = [:]
        for slot in schedule.safeSlots {
            groups[slot.weekday, default: [:]][slot.studentID, default: []].append(slot)
        }
        var kept: [Weekday: [String: CDScheduleSlot]] = [:]
        var extras: [CDScheduleSlot] = []
        for (weekday, byStudent) in groups {
            for (studentID, slots) in byStudent {
                let ordered = slots.sorted(by: madeFirst)
                kept[weekday, default: [:]][studentID] = ordered.first
                extras += ordered.dropFirst()
            }
        }
        return (kept, extras)
    }

    @discardableResult
    static func apply(
        _ days: [Weekday: [Entry]], to schedule: CDSchedule, in context: NSManagedObjectContext, now: Date = Date()
    ) -> Outcome {
        var outcome = Outcome()
        let (kept, extras) = slotsByDay(of: schedule)
        for extra in extras {
            context.delete(extra)
            outcome.deleted += 1
        }
        let scheduleID = schedule.id?.uuidString ?? ""
        for weekday in Weekday.allCases {
            let stored = kept[weekday] ?? [:]
            let entries = ordered(days[weekday] ?? [])
            let wanted = Set(entries.map(\.studentID))
            for (index, entry) in entries.enumerated() {
                let time = entry.timeString.trimmed()
                let timeString: String? = time.isEmpty ? nil : time
                if let slot = stored[entry.studentID] {
                    if update(slot, timeString: timeString, sortOrder: Int64(index), scheduleID: scheduleID, now: now) {
                        outcome.updated += 1
                    }
                } else {
                    let slot = CDScheduleSlot(context: context)
                    slot.scheduleID = scheduleID
                    slot.studentID = entry.studentID
                    slot.weekday = weekday
                    slot.timeString = timeString
                    slot.sortOrder = Int64(index)
                    slot.schedule = schedule
                    outcome.inserted += 1
                }
            }
            for (studentID, slot) in stored where !wanted.contains(studentID) {
                context.delete(slot)
                outcome.deleted += 1
            }
        }
        return outcome
    }

    /// Assigns only what differs, so an unchanged slot isn't rewritten.
    private static func update(
        _ slot: CDScheduleSlot, timeString: String?, sortOrder: Int64, scheduleID: String, now: Date
    ) -> Bool {
        var changed = false
        if slot.timeString != timeString {
            slot.timeString = timeString
            changed = true
        }
        if slot.sortOrder != sortOrder {
            slot.sortOrder = sortOrder
            changed = true
        }
        if slot.scheduleID != scheduleID {
            slot.scheduleID = scheduleID
            changed = true
        }
        if changed { slot.modifiedAt = now }
        return changed
    }

    /// The slot made first, then the lower id: the same answer on every
    /// device. Times are compared to the millisecond, as iCloud keeps them.
    private static func madeFirst(_ lhs: CDScheduleSlot, _ rhs: CDScheduleSlot) -> Bool {
        let lhsMade = DataCleanupService.millisecondKey(lhs.createdAt) ?? .max
        let rhsMade = DataCleanupService.millisecondKey(rhs.createdAt) ?? .max
        if lhsMade != rhsMade { return lhsMade < rhsMade }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }
}
