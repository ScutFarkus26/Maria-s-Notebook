// PrepChecklistViewModel.swift
// ViewModel for the Classroom Environment Prep Checklist hub.

import SwiftUI
import CoreData

@Observable @MainActor
final class PrepChecklistViewModel {
    private(set) var checklists: [CDPrepChecklist] = []
    private(set) var isLoading = false

    var todayCompletions: [String: Date] = [:]
    var streakData: [UUID: Int] = [:]
    var showingEditor = false
    var showingHistory = false
    var editingChecklist: CDPrepChecklist?

    // MARK: - Load

    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        checklists = PrepChecklistService.fetchActiveChecklists(in: context)

        // Load completions and streaks for all checklists
        var allCompletions: [String: Date] = [:]
        var allStreaks: [UUID: Int] = [:]

        for checklist in checklists {
            let completions = PrepChecklistService.fetchTodayCompletions(for: checklist, in: context)
            allCompletions.merge(completions) { _, new in new }

            if let checklistID = checklist.id {
                allStreaks[checklistID] = PrepChecklistService.calculateStreak(for: checklist, in: context)
            }
        }

        todayCompletions = allCompletions
        streakData = allStreaks
    }

    // MARK: - Completion

    func toggleItem(_ item: CDPrepChecklistItem, context: NSManagedObjectContext) {
        let isNowCompleted = PrepChecklistService.toggleItem(item, in: context)
        let itemIDStr = item.id?.uuidString ?? ""

        if isNowCompleted {
            todayCompletions[itemIDStr] = Date()
        } else {
            todayCompletions.removeValue(forKey: itemIDStr)
        }

        // Recalculate streak for the parent checklist
        if let checklist = item.checklist, let checklistID = checklist.id {
            streakData[checklistID] = PrepChecklistService.calculateStreak(for: checklist, in: context)
        }
    }

    func resetChecklist(_ checklist: CDPrepChecklist, context: NSManagedObjectContext) {
        PrepChecklistService.resetChecklist(checklist, in: context)
        loadData(context: context)
    }

    func isItemCompleted(_ item: CDPrepChecklistItem) -> Bool {
        guard let itemID = item.id?.uuidString else { return false }
        return todayCompletions[itemID] != nil
    }

    func completionPercentage(for checklist: CDPrepChecklist) -> Double {
        PrepChecklistService.completionPercentage(for: checklist, todayCompletions: todayCompletions)
    }

    func completedCount(for checklist: CDPrepChecklist) -> Int {
        checklist.itemsArray.filter { isItemCompleted($0) }.count
    }

    func streak(for checklist: CDPrepChecklist) -> Int {
        guard let id = checklist.id else { return 0 }
        return streakData[id] ?? 0
    }

    // MARK: - CRUD

    @discardableResult
    func createChecklist(
        name: String,
        icon: String = "checklist.checked",
        colorHex: String = "#007AFF",
        scheduleType: PrepScheduleType = .daily,
        context: NSManagedObjectContext
    ) -> CDPrepChecklist {
        let checklist = PrepChecklistService.createChecklist(
            name: name, icon: icon, colorHex: colorHex,
            scheduleType: scheduleType, in: context
        )
        loadData(context: context)
        return checklist
    }

    func deleteChecklist(_ checklist: CDPrepChecklist, context: NSManagedObjectContext) {
        PrepChecklistService.deleteChecklist(checklist, in: context)
        loadData(context: context)
    }

    @discardableResult
    func addItem(
        to checklist: CDPrepChecklist,
        title: String,
        category: String = "",
        context: NSManagedObjectContext
    ) -> CDPrepChecklistItem {
        let item = PrepChecklistService.addItem(to: checklist, title: title, category: category, in: context)
        loadData(context: context)
        return item
    }

    func deleteItem(_ item: CDPrepChecklistItem, context: NSManagedObjectContext) {
        PrepChecklistService.deleteItem(item, in: context)
        loadData(context: context)
    }
}
