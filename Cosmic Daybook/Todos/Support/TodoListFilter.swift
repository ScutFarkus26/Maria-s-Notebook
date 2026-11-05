// TodoListFilter.swift
// The Todos screen's lists.

import SwiftUI

// MARK: - Todo Filter

/// The Todos screen's own lists (simplify round two, 2026-11-03). Tide is the
/// to-do list; the notebook keeps what only it makes, the automatic work
/// check-ins, plus the to-dos shared with Tide (by Tide list, in the sidebar's
/// "From Tide" section), any typed here that haven't reached Tide yet, and
/// what is done. "Not yet in Tide" shows only while it holds something, so
/// nothing open is ever out of sight.
enum TodoListFilter: String, CaseIterable, Identifiable {
    case checkIns
    case notInTide
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkIns: return "Check-ins"
        case .notInTide: return "Not yet in Tide"
        case .done: return "Done"
        }
    }

    var icon: String {
        switch self {
        case .checkIns: return "arrow.triangle.2.circlepath"
        case .notInTide: return "tray.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .checkIns: return .orange
        case .notInTide: return .blue
        case .done: return .green
        }
    }

    var emptyMessage: String {
        switch self {
        case .checkIns: return "No check-ins waiting"
        case .notInTide: return "Every to-do is in Tide"
        case .done: return "Nothing done yet"
        }
    }

    /// Whether `todo` belongs in this list.
    func matches(_ todo: CDTodoItem) -> Bool {
        switch self {
        case .checkIns:
            return !todo.isCompleted && hasLinkedWork(todo)
        case .notInTide:
            return !todo.isCompleted && !hasLinkedWork(todo) && todo.tideLink == nil
        case .done:
            return todo.isCompleted
        }
    }

    /// A work check-in: a to-do the app made for a piece of work.
    private func hasLinkedWork(_ todo: CDTodoItem) -> Bool {
        !(todo.linkedWorkItemID ?? "").trimmed().isEmpty
    }

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
