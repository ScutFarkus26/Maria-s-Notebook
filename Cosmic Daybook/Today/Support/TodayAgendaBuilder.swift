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
    static func buildAgenda(
        lessons: [CDLessonAssignment],
        day: Date,
        context: NSManagedObjectContext
    ) -> [AgendaItem] {
        // 1. Build the complete set in default order (exclude presented lessons — they appear in the left column)
        let allItems: [AgendaItem] = lessons.filter { !$0.isPresented }.map { .lesson($0) }

        // 2. Fetch saved order
        let savedOrder = fetchSavedOrder(for: day, context: context)

        if savedOrder.isEmpty {
            return allItems
        }

        // 3. Build ordered result
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

        // 4. Append any new items that weren't in the saved order
        for item in allItems where !usedIDs.contains(item.id) {
            ordered.append(item)
        }

        return ordered
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
    /// `entries` are the rows on screen, which under a level filter are only
    /// some of the day's: the rows saved for items not on screen keep their
    /// places (`mergedOrder`), so reordering under one level no longer erases
    /// the order arranged under another.
    private static func replaceOrder(
        with entries: [(AgendaItemType, UUID)],
        replacing: (AgendaItemType) -> Bool,
        day: Date,
        context: NSManagedObjectContext
    ) {
        let dayStart = AppCalendar.startOfDay(day)

        // Delete this kind's existing entries for the day, remembering their order
        var saved: [(AgendaItemType, UUID)] = []
        for entry in fetchSavedOrder(for: day, context: context) where replacing(entry.itemType) {
            if let itemID = entry.itemID { saved.append((entry.itemType, itemID)) }
            context.delete(entry)
        }

        // Write new entries
        for (index, (type, id)) in mergedOrder(saved: saved, shown: entries).enumerated() {
            let entry = CDTodayAgendaOrder(context: context)
            entry.day = dayStart
            entry.itemType = type
            entry.itemID = id
            entry.position = Int64(index)
        }

        context.safeSave()
    }

    /// The saved order with the shown items rearranged among themselves: each
    /// slot a shown item held now takes the next shown item in its new order,
    /// a hidden item keeps its slot, and shown items with no slot yet follow at
    /// the end. Repeated ids keep their first slot.
    static func mergedOrder(
        saved: [(AgendaItemType, UUID)], shown: [(AgendaItemType, UUID)]
    ) -> [(AgendaItemType, UUID)] {
        let shownIDs = Set(shown.map(\.1))
        var queue = shown[...]
        var merged: [(AgendaItemType, UUID)] = []
        var placed = Set<UUID>()
        for entry in saved where placed.insert(entry.1).inserted {
            if shownIDs.contains(entry.1) {
                if let next = queue.popFirst() { merged.append(next) }
            } else {
                merged.append(entry)
            }
        }
        merged.append(contentsOf: queue)
        return merged
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
