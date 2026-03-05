// TodoListFilter.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI

// MARK: - Todo Filter

enum TodoListFilter: String, CaseIterable, Identifiable {
    case inbox
    case today
    case upcoming
    case anytime
    case someday
    case completed
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .anytime: return "Anytime"
        case .someday: return "Someday"
        case .completed: return "Completed"
        case .all: return "All"
        }
    }

    var icon: String {
        switch self {
        case .inbox: return "tray.fill"
        case .today: return "star.fill"
        case .upcoming: return "calendar"
        case .anytime: return "clock"
        case .someday: return "moon.zzz"
        case .completed: return "checkmark.circle.fill"
        case .all: return "list.bullet"
        }
    }

    var color: Color {
        switch self {
        case .inbox: return .blue
        case .today: return .orange
        case .upcoming: return .purple
        case .anytime: return .gray
        case .someday: return .brown
        case .completed: return .green
        case .all: return .primary
        }
    }

    var emptyMessage: String {
        switch self {
        case .inbox: return "Your inbox is empty"
        case .today: return "No tasks scheduled for today"
        case .upcoming: return "No upcoming tasks"
        case .anytime: return "No unscheduled tasks"
        case .someday: return "No someday tasks"
        case .completed: return "No completed tasks yet"
        case .all: return "Add a task to get started"
        }
    }

    func matches(_ todo: TodoItem) -> Bool {
        switch self {
        case .inbox:
            return !todo.isCompleted && !todo.isSomeday && todo.tags.isEmpty
        case .today:
            return !todo.isCompleted && !todo.isSomeday && todo.isScheduledForToday
        case .upcoming:
            let hasDate = todo.scheduledDate != nil || todo.dueDate != nil
            return !todo.isCompleted && !todo.isSomeday && hasDate && !todo.isScheduledForToday
        case .anytime:
            return !todo.isCompleted && !todo.isSomeday && todo.scheduledDate == nil && todo.dueDate == nil
        case .someday:
            return !todo.isCompleted && todo.isSomeday
        case .completed:
            return todo.isCompleted
        case .all:
            return true
        }
    }
}
