// TodoListScope.swift
// What the Todos screen's list shows, and the batch selection made in it.

import CoreData
import Foundation

/// The list the Todos screen shows: one sidebar pick (a filter or a Tide
/// list) narrowed by the search text. A Tide list wins over the filter.
struct TodoListScope: Equatable {
    var filter: TodoListFilter?
    var tideList: String?
    var searchText: String = ""

    /// Whether `todo` is in this list, before Hide Completed is applied.
    func contains(_ todo: CDTodoItem) -> Bool {
        let inList: Bool
        if let tideList {
            inList = todo.tideListFile == tideList
        } else {
            inList = (filter ?? .checkIns).matches(todo)
        }
        guard inList else { return false }
        return searchText.isEmpty
            || todo.title.localizedCaseInsensitiveContains(searchText)
            || todo.notes.localizedCaseInsensitiveContains(searchText)
    }

    /// The to-dos the More menu's Clear Completed deletes: the completed ones
    /// in this list, whether or not Hide Completed is on. It used to delete
    /// every completed to-do in the notebook, from any list (bug hunt
    /// 2026-11-03, #50).
    func completedToClear(from todos: [CDTodoItem]) -> [CDTodoItem] {
        todos.filter { $0.isCompleted && contains($0) }
    }
}

/// The to-dos picked in Select mode, and the list they were picked in.
struct TodoBatchSelection {
    var ids: Set<UUID> = []
    private(set) var scope: TodoListScope?

    /// Called whenever the screen's list changes (a sidebar pick, a filter,
    /// a Tide list or the search text). A new list starts with nothing
    /// selected: the selection used to carry over, so a batch Delete took
    /// to-dos no longer on screen (bug hunt 2026-11-03, #51).
    mutating func show(_ newScope: TodoListScope) {
        if newScope != scope { ids.removeAll() }
        scope = newScope
    }

    /// The selected to-dos among `todos`, in their order.
    func selected(in todos: [CDTodoItem]) -> [CDTodoItem] {
        todos.filter { $0.id.map(ids.contains) ?? false }
    }
}
