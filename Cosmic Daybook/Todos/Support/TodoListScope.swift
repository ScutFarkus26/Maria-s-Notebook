// TodoListScope.swift
// What the Todos screen's list shows, and the batch selection made in it.

import CoreData
import Foundation

/// The list the Todos screen shows: one sidebar pick (a filter, a tag, a tag
/// folder or a Tide list) narrowed by the search text. The first pick that is
/// set wins, in the order Tide list, folder, tag, filter.
struct TodoListScope: Equatable {
    var filter: TodoListFilter?
    var tag: String?
    var folder: String?
    var tideList: String?
    var searchText: String = ""

    /// Whether `todo` is in this list on the day `today` falls on, before
    /// Hide Completed is applied.
    func contains(_ todo: CDTodoItem, today: Date = Date()) -> Bool {
        let inList: Bool
        if let tideList {
            inList = todo.tideListFile == tideList
        } else if let folder {
            // Any tag nested under this folder.
            inList = todo.tagsArray.contains {
                TodoTagHelper.tagPathComponents($0).count > 1 && TodoTagHelper.rootTagName($0) == folder
            }
        } else if let tag {
            inList = todo.tagsArray.contains(tag)
        } else {
            inList = (filter ?? .inbox).matches(todo, today: today)
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
    func completedToClear(from todos: [CDTodoItem], today: Date = Date()) -> [CDTodoItem] {
        todos.filter { $0.isCompleted && contains($0, today: today) }
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
