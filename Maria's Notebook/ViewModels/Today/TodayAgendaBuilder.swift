// TodayAgendaBuilder.swift
// Builds the unified agenda by merging lessons and work items with persisted ordering.

import Foundation
import OSLog
import SwiftData

enum TodayAgendaBuilder {

    private static let logger = Logger.app_

    // Builds the unified agenda by merging items with persisted order.
    // Items with a saved position appear first (in position order).
    // New items (not in saved order) are appended at the end in default order.
    // Work items with group/flexible check-in styles are merged into grouped rows.
    // swiftlint:disable:next function_parameter_count
    static func buildAgenda(
        lessons: [LessonAssignment],
        overdueSchedule: [ScheduledWorkItem],
        todaysSchedule: [ScheduledWorkItem],
        staleFollowUps: [FollowUpWorkItem],
        day: Date,
        context: ModelContext
    ) -> [AgendaItem] {
        // 1. Group scheduled work by checkInStyle + lessonID
        let allScheduled = overdueSchedule + todaysSchedule
        let groupedScheduledItems = groupScheduledWork(allScheduled)
        let groupedFollowUpItems = groupFollowUpWork(staleFollowUps)

        // 2. Build the complete set in default order (exclude presented lessons — they appear in the left column)
        var allItems: [AgendaItem] = []
        allItems += lessons.filter { !$0.isPresented }.map { .lesson($0) }
        allItems += groupedScheduledItems
        allItems += groupedFollowUpItems

        // 3. Fetch saved order
        let savedOrder = fetchSavedOrder(for: day, context: context)

        if savedOrder.isEmpty {
            return allItems
        }

        // 4. Build ordered result
        let itemsByID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered: [AgendaItem] = []
        var usedIDs = Set<UUID>()

        for entry in savedOrder {
            if let item = itemsByID[entry.itemID] {
                ordered.append(item)
                usedIDs.insert(entry.itemID)
            }
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

    /// Groups follow-up work items by check-in style and lessonID.
    private static func groupFollowUpWork(_ items: [FollowUpWorkItem]) -> [AgendaItem] {
        var individualItems: [AgendaItem] = []
        var groupBuckets: [String: [FollowUpWorkItem]] = [:]
        var groupOrder: [String] = []

        for item in items {
            let style = item.work.checkInStyle
            if style == .individual {
                individualItems.append(.followUp(item))
            } else {
                let key = item.work.lessonID
                if groupBuckets[key] == nil { groupOrder.append(key) }
                groupBuckets[key, default: []].append(item)
            }
        }

        var result: [AgendaItem] = []
        for key in groupOrder {
            guard let bucket = groupBuckets[key] else { continue }
            if bucket.count == 1 {
                result.append(.followUp(bucket[0]))
            } else {
                result.append(.groupedFollowUp(bucket))
            }
        }
        result += individualItems
        return result
    }

    /// Persists the current agenda order for a day.
    @MainActor static func saveOrder(
        items: [AgendaItem],
        day: Date,
        context: ModelContext
    ) {
        let dayStart = AppCalendar.startOfDay(day)

        // Delete existing entries for this day
        do {
            var descriptor = FetchDescriptor<TodayAgendaOrder>(
                predicate: #Predicate { $0.day == dayStart }
            )
            descriptor.fetchLimit = 200
            let existing = try context.fetch(descriptor)
            for entry in existing {
                context.delete(entry)
            }
        } catch {
            // Continue — we'll write new entries regardless
        }

        // Write new entries
        for (index, item) in items.enumerated() {
            let entry = TodayAgendaOrder(
                day: dayStart,
                itemType: item.itemType,
                itemID: item.id,
                position: index
            )
            context.insert(entry)
        }

        do {
            try context.save()
        } catch {
            logger.warning("Failed to save agenda order: \(error)")
        }
    }

    /// Deletes agenda order entries older than 30 days.
    @MainActor static func cleanupOldOrders(context: ModelContext) {
        let cutoff = AppCalendar.startOfDay(
            Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        )
        do {
            var descriptor = FetchDescriptor<TodayAgendaOrder>(
                predicate: #Predicate { $0.day < cutoff }
            )
            descriptor.fetchLimit = 1000
            let old = try context.fetch(descriptor)
            guard !old.isEmpty else { return }
            for entry in old {
                context.delete(entry)
            }
            try context.save()
        } catch {
            logger.warning("Failed to cleanup old agenda orders: \(error)")
        }
    }

    // MARK: - Private

    private static func fetchSavedOrder(for day: Date, context: ModelContext) -> [TodayAgendaOrder] {
        let dayStart = AppCalendar.startOfDay(day)
        do {
            var descriptor = FetchDescriptor<TodayAgendaOrder>(
                predicate: #Predicate { $0.day == dayStart },
                sortBy: [SortDescriptor(\.position)]
            )
            descriptor.fetchLimit = 200
            return try context.fetch(descriptor)
        } catch {
            return []
        }
    }
}
