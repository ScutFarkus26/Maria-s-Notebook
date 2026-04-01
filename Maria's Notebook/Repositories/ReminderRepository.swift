//
//  ReminderRepository.swift
//  Maria's Notebook
//
//  Repository for CDReminder entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
struct ReminderRepository: SavingRepository {
    typealias Model = CDReminder

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDReminder by ID
    func fetchReminder(id: UUID) -> CDReminder? {
        let request = CDFetchRequest(CDReminder.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    /// Fetch multiple Reminders with optional filtering and sorting
    func fetchReminders(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "dueDate", ascending: true)]
    ) -> [CDReminder] {
        let request = CDFetchRequest(CDReminder.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        return context.safeFetch(request)
    }

    /// Fetch incomplete reminders
    func fetchIncompleteReminders() -> [CDReminder] {
        fetchReminders(predicate: NSPredicate(format: "isCompleted == NO"))
    }

    /// Fetch reminders due today or overdue
    func fetchDueToday(calendar: Calendar = .current) -> [CDReminder] {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let allIncomplete = fetchIncompleteReminders()
        return allIncomplete.filter { reminder in
            guard let dueDate = reminder.dueDate else { return false }
            return dueDate < endOfDay
        }
    }

    /// Fetch reminder by EventKit ID (for sync)
    func fetchReminder(byEventKitID eventKitID: String) -> CDReminder? {
        let request = CDFetchRequest(CDReminder.self)
        request.predicate = NSPredicate(format: "eventKitReminderID == %@", eventKitID)
        return context.safeFetchFirst(request)
    }

    // MARK: - Create

    /// Create a new CDReminder
    @discardableResult
    func createReminder(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        eventKitReminderID: String? = nil,
        eventKitCalendarID: String? = nil
    ) -> CDReminder {
        let reminder = CDReminder(context: context)
        reminder.title = title
        reminder.dueDate = dueDate
        reminder.eventKitReminderID = eventKitReminderID
        reminder.eventKitCalendarID = eventKitCalendarID
        if eventKitReminderID != nil {
            reminder.notes = notes
        } else {
            reminder.setLegacyNoteText(notes, in: context)
        }
        return reminder
    }

    // MARK: - Update

    /// Update an existing CDReminder's properties
    @discardableResult
    func updateReminder(
        id: UUID,
        title: String? = nil,
        notes: String? = nil,
        dueDate: Date? = nil
    ) -> Bool {
        guard let reminder = fetchReminder(id: id) else { return false }

        if let title { reminder.title = title }
        if let notes {
            if reminder.eventKitReminderID != nil {
                reminder.notes = notes.isEmpty ? nil : notes
            } else {
                reminder.notes = nil
                reminder.setLegacyNoteText(notes, in: context)
            }
        }
        if let dueDate { reminder.dueDate = dueDate }
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

    /// Delete a CDReminder by ID
    func deleteReminder(id: UUID) throws {
        guard let reminder = fetchReminder(id: id) else { return }
        context.delete(reminder)
        try context.save()
    }
}
