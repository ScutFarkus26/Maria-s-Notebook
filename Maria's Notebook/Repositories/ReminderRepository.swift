//
//  ReminderRepository.swift
//  Maria's Notebook
//
//  Repository for Reminder entity CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import SwiftData

@MainActor
struct ReminderRepository: SavingRepository {
    typealias Model = Reminder

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a Reminder by ID
    func fetchReminder(id: UUID) -> Reminder? {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Fetch multiple Reminders with optional filtering and sorting
    func fetchReminders(
        predicate: Predicate<Reminder>? = nil,
        sortBy: [SortDescriptor<Reminder>] = [SortDescriptor(\.dueDate)]
    ) -> [Reminder] {
        var descriptor = FetchDescriptor<Reminder>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetch incomplete reminders
    func fetchIncompleteReminders() -> [Reminder] {
        let predicate = #Predicate<Reminder> { !$0.isCompleted }
        return fetchReminders(predicate: predicate)
    }

    /// Fetch reminders due today or overdue
    func fetchDueToday(calendar: Calendar = .current) -> [Reminder] {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        // Fetch all incomplete reminders and filter in memory to avoid SwiftData predicate issues with optionals
        let allIncomplete = fetchIncompleteReminders()
        return allIncomplete.filter { reminder in
            guard let dueDate = reminder.dueDate else { return false }
            return dueDate < endOfDay
        }
    }

    /// Fetch reminder by EventKit ID (for sync)
    func fetchReminder(byEventKitID eventKitID: String) -> Reminder? {
        let predicate = #Predicate<Reminder> { $0.eventKitReminderID == eventKitID }
        return fetchReminders(predicate: predicate).first
    }

    // MARK: - Create

    /// Create a new Reminder
    @discardableResult
    func createReminder(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        eventKitReminderID: String? = nil,
        eventKitCalendarID: String? = nil
    ) -> Reminder {
        let reminder = Reminder(
            title: title,
            notes: notes,
            dueDate: dueDate,
            eventKitReminderID: eventKitReminderID,
            eventKitCalendarID: eventKitCalendarID
        )
        context.insert(reminder)
        return reminder
    }

    // MARK: - Update

    /// Update an existing Reminder's properties
    @discardableResult
    func updateReminder(
        id: UUID,
        title: String? = nil,
        notes: String? = nil,
        dueDate: Date? = nil
    ) -> Bool {
        guard let reminder = fetchReminder(id: id) else { return false }

        if let title = title {
            reminder.title = title
        }
        if let notes = notes {
            reminder.notes = notes.isEmpty ? nil : notes
        }
        if let dueDate = dueDate {
            reminder.dueDate = dueDate
        }
        reminder.updatedAt = Date()

        return true
    }

    /// Mark a reminder as completed
    @discardableResult
    func markCompleted(id: UUID) -> Bool {
        guard let reminder = fetchReminder(id: id) else { return false }
        reminder.markCompleted()
        return true
    }

    /// Mark a reminder as incomplete
    @discardableResult
    func markIncomplete(id: UUID) -> Bool {
        guard let reminder = fetchReminder(id: id) else { return false }
        reminder.markIncomplete()
        return true
    }

    // MARK: - Delete

    /// Delete a Reminder by ID
    func deleteReminder(id: UUID) throws {
        guard let reminder = fetchReminder(id: id) else { return }
        context.delete(reminder)
        try context.save()
    }
}
