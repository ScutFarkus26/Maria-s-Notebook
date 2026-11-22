// TodoListFilter.swift
// When a to-do is on Today.

import Foundation

// MARK: - Todo Filter

/// Today's rules for a to-do. They were the Todos screen's lists too until
/// that screen was taken out on 2026-11-22; Today's to-do section, meetings'
/// "For Me to Do" and the forms remain, and Tide is the to-do list.
enum TodoListFilter {
    /// Today's rule for a to-do: open, and planned or due by `today`; a
    /// someday to-do keeps its deadline, and once that comes it is due like
    /// any other (bug hunt 2026-11-03, #57). The Today screen's to-do section
    /// reads it.
    static func isOnToday(_ todo: CDTodoItem, today: Date = Date()) -> Bool {
        guard !todo.isCompleted else { return false }
        return todo.isSomeday ? isDue(todo, by: today) : isDueOrPlanned(todo, by: today)
    }

    /// Whether a todo's When date or its deadline falls on `today` or
    /// earlier. Today showed only todos planned or due today, so an overdue
    /// todo, or one due today but planned for later, dropped out of it
    /// (bug hunt 2026-10-10, P2 #25).
    static func isDueOrPlanned(_ todo: CDTodoItem, by today: Date) -> Bool {
        let tomorrow = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(today))
        if let scheduled = todo.scheduledDate, scheduled < tomorrow { return true }
        if let due = todo.dueDate, due < tomorrow { return true }
        return false
    }

    /// Whether a todo's deadline falls on `today` or earlier.
    static func isDue(_ todo: CDTodoItem, by today: Date) -> Bool {
        guard let due = todo.dueDate else { return false }
        return due < AppCalendar.addingDays(1, to: AppCalendar.startOfDay(today))
    }
}
