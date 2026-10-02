// TodayLinkedTodosLoader.swift
// Reads the open todos linked to work, once per Today reload, and folds them
// onto the work rows on screen (`TodayLinkedTodos`).
//
// One narrow fetch: open todos whose `linkedWorkItemID` is set. Most todos
// name no work, so this is a handful of rows, not the todo table.

import CoreData
import Foundation

enum TodayLinkedTodosLoader {

    /// - Parameters:
    ///   - workIDsOnScreen: every work id with a row on Today (Gone quiet,
    ///     and the due check-ins in the Todos list).
    ///   - day: the day Today shows; a todo due before it is overdue.
    static func load(
        workIDsOnScreen: Set<UUID>,
        day: Date,
        calendar: Calendar,
        context: NSManagedObjectContext
    ) -> TodayLinkedTodos {
        guard !workIDsOnScreen.isEmpty else { return .empty }
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = NSPredicate(
            format: "isCompleted == NO AND linkedWorkItemID != nil AND linkedWorkItemID != %@", ""
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: true)]
        let todos = context.safeFetch(request).compactMap { todo -> TodayLinkedTodos.Todo? in
            guard let id = todo.id else { return nil }
            return TodayLinkedTodos.Todo(id: id, linkedWorkItemID: todo.linkedWorkItemID, dueDate: todo.dueDate)
        }
        return TodayLinkedTodos.build(
            todos: todos, workIDsOnScreen: workIDsOnScreen, referenceDay: day, calendar: calendar
        )
    }
}
