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
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    /// Fetch incomplete reminders
    func fetchIncompleteReminders() -> [CDReminder] {
        fetchReminders(predicate: NSPredicate(format: "isCompleted == NO"))
    }

    /// Fetch reminder by EventKit ID (for sync)
    func fetchReminder(byEventKitID eventKitID: String) -> CDReminder? {
        let request = CDFetchRequest(CDReminder.self)
        request.predicate = NSPredicate(format: "eventKitReminderID == %@", eventKitID)
        return context.safeFetchFirst(request)
    }

    // MARK: - Update

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

}
