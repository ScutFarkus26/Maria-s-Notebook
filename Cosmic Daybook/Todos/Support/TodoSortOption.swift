// TodoSortOption.swift
// Sort options for the todo list

import Foundation

enum TodoSortOption: String, CaseIterable, Identifiable {
    case dueDate = "Due Date"
    case priority = "Priority"
    case title = "Title"
    case created = "Created"

    var id: String { rawValue }

    var title: String { rawValue }
}
