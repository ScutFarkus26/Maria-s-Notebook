// TodoMainView+Filtering.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import SwiftData

extension TodoMainView {
    var filteredTodos: [TodoItem] {
        var todos: [TodoItem]
        let isTagView: Bool
        if let folder = selectedFolder {
            // Show all todos that have any tag belonging to this folder
            let folderTags = Set(allUsedTags.filter {
                TodoTagHelper.tagPathComponents($0).count > 1 && TodoTagHelper.rootTagName($0) == folder
            })
            todos = allTodos.filter { todo in
                todo.tags.contains(where: { folderTags.contains($0) })
            }
            isTagView = true
        } else if let tag = selectedTag {
            todos = allTodos.filter { $0.tags.contains(tag) }
            isTagView = true
        } else {
            let filter = selectedFilter ?? .inbox
            todos = allTodos.filter { filter.matches($0) }
            isTagView = false
        }

        if isTagView && hideCompletedInTags {
            todos = todos.filter { !$0.isCompleted }
        }

        let searchFiltered = searchText.isEmpty ? todos : todos.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }

        return searchFiltered.sorted { lhs, rhs in
            // Completed items always go to bottom
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }

            // Then sort by selected option
            switch sortBy {
            case .dueDate:
                if let lhsDate = lhs.effectiveDate, let rhsDate = rhs.effectiveDate {
                    return lhsDate < rhsDate
                }
                return lhs.effectiveDate != nil && rhs.effectiveDate == nil
            case .priority:
                return lhs.priority.sortOrder < rhs.priority.sortOrder
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .created:
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    // PERF: Uses cached counts computed in a single pass over allTodos (refreshTagCaches).
    // Previously each call scanned allTodos independently.
    func countForFilter(_ filter: TodoListFilter) -> Int {
        guard filter != .all else { return 0 }
        return cachedFilterCounts[filter] ?? 0
    }

    func countForTag(_ tag: String) -> Int {
        cachedTagCounts[tag] ?? 0
    }
}
