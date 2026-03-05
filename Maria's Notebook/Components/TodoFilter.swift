import SwiftUI
import SwiftData

enum TodoFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"
    case today = "Today"
    case thisWeek = "This Week"
    case someday = "Someday"
    case overdue = "Overdue"
    case highPriority = "High Priority"
    case hasSubtasks = "With Checklist"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .active: return "circle"
        case .completed: return "checkmark.circle.fill"
        case .today: return "calendar.badge.clock"
        case .thisWeek: return "calendar"
        case .someday: return "moon.zzz"
        case .overdue: return "exclamationmark.triangle.fill"
        case .highPriority: return "flag.fill"
        case .hasSubtasks: return "checklist"
        }
    }

    var color: Color {
        switch self {
        case .all: return .primary
        case .active: return .blue
        case .completed: return .green
        case .today: return .orange
        case .thisWeek: return .purple
        case .someday: return .brown
        case .overdue: return .red
        case .highPriority: return .red
        case .hasSubtasks: return .indigo
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "Add a task to get started"
        case .active: return "All done! No active tasks"
        case .completed: return "No completed tasks yet"
        case .today: return "No tasks due today"
        case .thisWeek: return "No tasks due this week"
        case .someday: return "No someday tasks"
        case .overdue: return "You're all caught up!"
        case .highPriority: return "No high priority tasks"
        case .hasSubtasks: return "No tasks with checklists"
        }
    }

    func matches(_ todo: TodoItem) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return !todo.isCompleted && !todo.isSomeday
        case .completed:
            return todo.isCompleted
        case .today:
            return todo.isScheduledForToday && !todo.isCompleted
        case .thisWeek:
            return todo.isDueThisWeek && !todo.isCompleted
        case .someday:
            return todo.isSomeday && !todo.isCompleted
        case .overdue:
            return todo.isOverdue
        case .highPriority:
            return todo.priority == .high && !todo.isCompleted
        case .hasSubtasks:
            return !(todo.subtasks ?? []).isEmpty
        }
    }
}
