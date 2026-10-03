// TodayAgendaBuilder.swift
// Builds the unified agenda by merging lessons and work items with persisted ordering.
// Scheduled meetings are not on it: they have a Meetings section of their own,
// whose order is saved beside the agenda's (`saveMeetingOrder`).
// Neither is quiet work: Gone quiet groups it here (`groupFollowUpWork`) and
// lists it in its own section, most quiet first.

import Foundation
import CoreData

enum TodayAgendaBuilder {

    // Builds the unified agenda by merging items with persisted order.
    // Items with a saved position appear first (in position order).
    // New items (not in saved order) are appended at the end in default order.
    // Work items with group/flexible check-in styles are merged into grouped rows.
    static func buildAgenda(
        lessons: [CDLessonAssignment],
        overdueSchedule: [ScheduledWorkItem],
        todaysSchedule: [ScheduledWorkItem],
        day: Date,
        context: NSManagedObjectContext
    ) -> [AgendaItem] {
        // 1. Group scheduled work by checkInStyle + lessonID
        let allScheduled = overdueSchedule + todaysSchedule
        let groupedScheduledItems = groupScheduledWork(allScheduled)

        // 2. Build the complete set in default order (exclude presented lessons — they appear in the left column)
        var allItems: [AgendaItem] = []
        allItems += lessons.filter { !$0.isPresented }.map { .lesson($0) }
        allItems += groupedScheduledItems

        // 3. Fetch saved order
        let savedOrder = fetchSavedOrder(for: day, context: context)

        if savedOrder.isEmpty {
            return allItems
        }

        // 4. Build ordered result
        let itemsByID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered: [AgendaItem] = []
        var usedIDs = Set<UUID>()

        // Two devices can each save a row for the same item; the first one
        // places it and the rest are ignored, as `orderMeetings` does.
        for entry in savedOrder {
            guard let entryItemID = entry.itemID, let item = itemsByID[entryItemID],
                  usedIDs.insert(entryItemID).inserted else { continue }
            ordered.append(item)
        }

        // 5. Append any new items that weren't in the saved order
        for item in allItems where !usedIDs.contains(item.id) {
            ordered.append(item)
        }

        return ordered
    }

    /// Groups scheduled work items by check-in style and lessonID.
    /// - Individual style: each item stays as a separate row
    /// - Group/Flexible style: items sharing the same lessonID merge into one grouped row
    private static func groupScheduledWork(_ items: [ScheduledWorkItem]) -> [AgendaItem] {
        var individualItems: [AgendaItem] = []
        // Key: lessonID, Value: accumulated items to group
        var groupBuckets: [String: [ScheduledWorkItem]] = [:]
        var groupOrder: [String] = []

        for item in items {
            let style = item.work.checkInStyle
            if style == .individual {
                individualItems.append(.scheduledWork(item))
            } else {
                let key = item.work.lessonID
                if groupBuckets[key] == nil { groupOrder.append(key) }
                groupBuckets[key, default: []].append(item)
            }
        }

        var result: [AgendaItem] = []
        // Emit grouped items in first-appearance order
        for key in groupOrder {
            guard let bucket = groupBuckets[key] else { continue }
            if bucket.count == 1 {
                // Single item doesn't need grouping even if style is group/flexible
                result.append(.scheduledWork(bucket[0]))
            } else {
                result.append(.groupedScheduledWork(bucket))
            }
        }
        result += individualItems
        return result
    }

    /// Groups quiet work by check-in style and lessonID, for Gone quiet: a
    /// group or flexible lesson's children share one row. Rows keep the order
    /// of the items given (most quiet first); a group sits where its most
    /// quiet child first appears.
    static func groupFollowUpWork(_ items: [FollowUpWorkItem]) -> [AgendaItem] {
        // Each slot is one row: an individual item, or a lesson's group key.
        enum Slot { case single(FollowUpWorkItem), group(String) }
        var slots: [Slot] = []
        var groupBuckets: [String: [FollowUpWorkItem]] = [:]

        for item in items {
            if item.work.checkInStyle == .individual {
                slots.append(.single(item))
            } else {
                let key = item.work.lessonID
                if groupBuckets[key] == nil { slots.append(.group(key)) }
                groupBuckets[key, default: []].append(item)
            }
        }

        return slots.compactMap { slot in
            switch slot {
            case .single(let item):
                return .followUp(item)
            case .group(let key):
                guard let bucket = groupBuckets[key], let first = bucket.first else { return nil }
                // A lone child of a group lesson needs no group row.
                return bucket.count == 1 ? .followUp(first) : .groupedFollowUp(bucket)
            }
        }
    }

    /// Persists the current agenda order for a day. The Meetings section's
    /// order shares the day's rows (`saveMeetingOrder`) and is left alone.
    static func saveOrder(
        items: [AgendaItem],
        day: Date,
        context: NSManagedObjectContext
    ) {
        replaceOrder(
            with: items.map { ($0.itemType, $0.id) },
            replacing: { $0 != .meeting },
            day: day,
            context: context
        )
    }

    /// Persists the Meetings section's order for a day, as `.meeting` rows
    /// beside the agenda's. The agenda's own rows are left alone.
    static func saveMeetingOrder(
        meetingIDs: [UUID],
        day: Date,
        context: NSManagedObjectContext
    ) {
        replaceOrder(
            with: meetingIDs.map { (.meeting, $0) },
            replacing: { $0 == .meeting },
            day: day,
            context: context
        )
    }

    /// The day's meetings in their saved order. Meetings with no saved
    /// position follow, in the order given.
    static func orderMeetings(
        _ meetings: [CDScheduledMeeting],
        day: Date,
        context: NSManagedObjectContext
    ) -> [CDScheduledMeeting] {
        guard meetings.count > 1 else { return meetings }
        let positions = Dictionary(
            fetchSavedOrder(for: day, context: context)
                .filter { $0.itemType == .meeting }
                .compactMap { entry in entry.itemID.map { ($0, entry.position) } },
            uniquingKeysWith: { first, _ in first }
        )
        guard !positions.isEmpty else { return meetings }
        return meetings.enumerated().sorted { lhs, rhs in
            let left = lhs.element.id.flatMap { positions[$0] }
            let right = rhs.element.id.flatMap { positions[$0] }
            switch (left, right) {
            case let (left?, right?): return left == right ? lhs.offset < rhs.offset : left < right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    // MARK: - Private

    /// Rewrites the day's order rows of the kinds `replacing` picks out.
    private static func replaceOrder(
        with entries: [(AgendaItemType, UUID)],
        replacing: (AgendaItemType) -> Bool,
        day: Date,
        context: NSManagedObjectContext
    ) {
        let dayStart = AppCalendar.startOfDay(day)

        // Delete this kind's existing entries for the day
        for entry in fetchSavedOrder(for: day, context: context) where replacing(entry.itemType) {
            context.delete(entry)
        }

        // Write new entries
        for (index, (type, id)) in entries.enumerated() {
            let entry = CDTodayAgendaOrder(context: context)
            entry.day = dayStart
            entry.itemType = type
            entry.itemID = id
            entry.position = Int64(index)
        }

        context.safeSave()
    }

    private static func fetchSavedOrder(for day: Date, context: NSManagedObjectContext) -> [CDTodayAgendaOrder] {
        let dayStart = AppCalendar.startOfDay(day)
        do {
            let request = CDFetchRequest(CDTodayAgendaOrder.self)
            request.predicate = NSPredicate(format: "day == %@", dayStart as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTodayAgendaOrder.position, ascending: true)]
            request.fetchLimit = 200
            return try context.fetch(request)
        } catch {
            return []
        }
    }
}
