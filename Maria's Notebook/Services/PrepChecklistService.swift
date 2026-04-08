// PrepChecklistService.swift
// Service for prep checklist completion tracking, reset, and streak calculation.

import Foundation
import CoreData

enum PrepChecklistService {

    // MARK: - Fetch Checklists

    @MainActor
    static func fetchActiveChecklists(in context: NSManagedObjectContext) -> [CDPrepChecklist] {
        let request = CDFetchRequest(CDPrepChecklist.self)
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return context.safeFetch(request)
    }

    @MainActor
    static func fetchAllChecklists(in context: NSManagedObjectContext) -> [CDPrepChecklist] {
        let request = CDFetchRequest(CDPrepChecklist.self)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return context.safeFetch(request)
    }

    // MARK: - Completions

    @MainActor
    static func fetchTodayCompletions(
        for checklist: CDPrepChecklist,
        in context: NSManagedObjectContext
    ) -> [String: Date] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let itemIDs = checklist.itemsArray.compactMap { $0.id?.uuidString }
        guard !itemIDs.isEmpty else { return [:] }

        let request = CDFetchRequest(CDPrepChecklistCompletion.self)
        request.predicate = NSPredicate(
            format: "checklistItemID IN %@ AND date >= %@ AND date < %@",
            itemIDs, today as NSDate, tomorrow as NSDate
        )

        let completions = context.safeFetch(request)
        var map: [String: Date] = [:]
        for completion in completions {
            if let completedAt = completion.completedAt {
                map[completion.checklistItemID] = completedAt
            }
        }
        return map
    }

    @MainActor
    static func toggleItem(
        _ item: CDPrepChecklistItem,
        completedBy: String = "",
        in context: NSManagedObjectContext
    ) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let itemIDStr = item.id?.uuidString ?? ""

        let request = CDFetchRequest(CDPrepChecklistCompletion.self)
        request.predicate = NSPredicate(
            format: "checklistItemID == %@ AND date >= %@ AND date < %@",
            itemIDStr, today as NSDate, tomorrow as NSDate
        )

        let existing = context.safeFetch(request)

        if let existing = existing.first {
            // Un-complete
            context.delete(existing)
            context.safeSave()
            return false
        } else {
            // Complete
            let completion = CDPrepChecklistCompletion(context: context)
            completion.checklistItemID = itemIDStr
            completion.date = today
            completion.completedBy = completedBy
            context.safeSave()
            return true
        }
    }

    // MARK: - Reset

    @MainActor
    static func resetChecklist(
        _ checklist: CDPrepChecklist,
        in context: NSManagedObjectContext
    ) {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let itemIDs = checklist.itemsArray.compactMap { $0.id?.uuidString }
        guard !itemIDs.isEmpty else { return }

        let request = CDFetchRequest(CDPrepChecklistCompletion.self)
        request.predicate = NSPredicate(
            format: "checklistItemID IN %@ AND date >= %@ AND date < %@",
            itemIDs, today as NSDate, tomorrow as NSDate
        )

        let completions = context.safeFetch(request)
        for completion in completions {
            context.delete(completion)
        }
        context.safeSave()
    }

    // MARK: - Streak

    @MainActor
    static func calculateStreak(
        for checklist: CDPrepChecklist,
        in context: NSManagedObjectContext
    ) -> Int {
        let items = checklist.itemsArray
        guard !items.isEmpty else { return 0 }

        let itemIDs = items.compactMap { $0.id?.uuidString }
        let itemCount = items.count

        let request = CDFetchRequest(CDPrepChecklistCompletion.self)
        request.predicate = NSPredicate(format: "checklistItemID IN %@", itemIDs)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        let completions = context.safeFetch(request)

        // Group completions by day
        var completionsByDay: [Date: Int] = [:]
        for completion in completions {
            guard let date = completion.date else { continue }
            let day = Calendar.current.startOfDay(for: date)
            completionsByDay[day, default: 0] += 1
        }

        // Walk backwards from today counting consecutive complete days
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())

        while true {
            let count = completionsByDay[checkDate] ?? 0
            if count >= itemCount {
                streak += 1
                guard let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = previousDay
            } else {
                break
            }
        }

        return streak
    }

    // MARK: - Completion Percentage

    @MainActor
    static func completionPercentage(
        for checklist: CDPrepChecklist,
        todayCompletions: [String: Date]
    ) -> Double {
        let totalItems = checklist.itemsArray.count
        guard totalItems > 0 else { return 0 }

        let completedCount = checklist.itemsArray.filter { item in
            guard let itemID = item.id?.uuidString else { return false }
            return todayCompletions[itemID] != nil
        }.count

        return Double(completedCount) / Double(totalItems)
    }

    // MARK: - CRUD

    @MainActor
    @discardableResult
    static func createChecklist(
        name: String,
        icon: String = "checklist.checked",
        colorHex: String = "#007AFF",
        scheduleType: PrepScheduleType = .daily,
        in context: NSManagedObjectContext
    ) -> CDPrepChecklist {
        let checklist = CDPrepChecklist(context: context)
        checklist.name = name
        checklist.icon = icon
        checklist.colorHex = colorHex
        checklist.scheduleType = scheduleType

        // Set sort order to end
        let existing = fetchAllChecklists(in: context)
        checklist.sortOrder = Int64(existing.count)

        context.safeSave()
        return checklist
    }

    @MainActor
    @discardableResult
    static func addItem(
        to checklist: CDPrepChecklist,
        title: String,
        category: String = "",
        in context: NSManagedObjectContext
    ) -> CDPrepChecklistItem {
        let item = CDPrepChecklistItem(context: context)
        item.checklistID = checklist.id?.uuidString ?? ""
        item.title = title
        item.category = category
        item.sortOrder = Int64(checklist.itemsArray.count)
        item.checklist = checklist
        context.safeSave()
        return item
    }

    @MainActor
    static func deleteChecklist(
        _ checklist: CDPrepChecklist,
        in context: NSManagedObjectContext
    ) {
        // Delete completions for all items
        let itemIDs = checklist.itemsArray.compactMap { $0.id?.uuidString }
        if !itemIDs.isEmpty {
            let request = CDFetchRequest(CDPrepChecklistCompletion.self)
            request.predicate = NSPredicate(format: "checklistItemID IN %@", itemIDs)
            let completions = context.safeFetch(request)
            for completion in completions {
                context.delete(completion)
            }
        }

        context.delete(checklist)
        context.safeSave()
    }

    @MainActor
    static func deleteItem(
        _ item: CDPrepChecklistItem,
        in context: NSManagedObjectContext
    ) {
        // Delete completions for this item
        if let itemID = item.id?.uuidString {
            let request = CDFetchRequest(CDPrepChecklistCompletion.self)
            request.predicate = NSPredicate(format: "checklistItemID == %@", itemID)
            let completions = context.safeFetch(request)
            for completion in completions {
                context.delete(completion)
            }
        }

        context.delete(item)
        context.safeSave()
    }
}
