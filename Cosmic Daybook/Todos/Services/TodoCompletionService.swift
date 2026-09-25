// TodoCompletionService.swift
// Completing a todo, recurrence included.
//
// Completion used to live inline in Today's `toggleTodoItem` and again in
// the old to-do list panel, each spawning the next occurrence of a
// repeating todo its own way. This is the one place that rule lives now;
// Today's toggle and the Watching list's "Clear" both call it.

import CoreData
import Foundation

@MainActor
enum TodoCompletionService {

    /// Marks the todo done and, when it repeats, inserts its next occurrence
    /// into the same context. Does not save.
    static func complete(_ todo: CDTodoItem, calendar: Calendar = AppCalendar.shared) {
        todo.isCompleted = true
        todo.completedAt = Date()
        if todo.recurrence != .none {
            // `CDTodoItem(context:)` inserts the new row as it is created.
            _ = nextOccurrence(after: todo, calendar: calendar)
        }
    }

    /// Reopens a completed todo. Does not save.
    static func reopen(_ todo: CDTodoItem) {
        todo.isCompleted = false
        todo.completedAt = nil
    }

    /// The next occurrence of a repeating todo, inserted into the todo's
    /// context, or nil when the pattern yields no next date. The base date is
    /// the due date the todo had, or today when it repeats after completion
    /// (or never had a due date); a scheduled date keeps its offset from the
    /// due date.
    @discardableResult
    static func nextOccurrence(after todo: CDTodoItem, calendar: Calendar) -> CDTodoItem? {
        let baseDate: Date
        let today = AppCalendar.startOfDay(Date())

        if todo.repeatAfterCompletion {
            baseDate = today
        } else {
            baseDate = todo.dueDate ?? today
        }

        let nextDueDate: Date?
        if todo.recurrence == .custom, todo.customIntervalDays > 0 {
            nextDueDate = calendar.date(byAdding: .day, value: Int(todo.customIntervalDays), to: baseDate)
        } else {
            nextDueDate = todo.recurrence.nextDate(after: baseDate)
        }

        guard let nextDueDate else { return nil }

        var nextScheduled: Date?
        if let scheduled = todo.scheduledDate, let due = todo.dueDate {
            let offset = calendar.dateComponents([.day], from: due, to: scheduled).day ?? 0
            nextScheduled = calendar.date(byAdding: .day, value: offset, to: nextDueDate)
        } else if todo.scheduledDate != nil {
            nextScheduled = nextDueDate
        }

        guard let context = todo.managedObjectContext else { return nil }
        let newTodo = CDTodoItem(context: context)
        newTodo.title = todo.title
        newTodo.notes = todo.notes
        newTodo.orderIndex = 0
        newTodo.studentIDs = todo.studentIDs
        newTodo.dueDate = nextDueDate
        newTodo.scheduledDate = nextScheduled
        newTodo.priority = todo.priority
        newTodo.recurrence = todo.recurrence
        newTodo.repeatAfterCompletion = todo.repeatAfterCompletion
        newTodo.customIntervalDays = todo.customIntervalDays
        newTodo.tags = todo.tags
        return newTodo
    }
}
