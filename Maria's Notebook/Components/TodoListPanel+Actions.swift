import OSLog
import SwiftUI
import CoreData

extension TodoListPanel {
    private static let logger = Logger.todos

    func addTodo() {
        let trimmed = newTodoTitle.trimmed()
        guard !trimmed.isEmpty else { return }

        let parseResult = TodoDateParser.parse(trimmed)
        let newTodo = CDTodoItem(context: viewContext)
        newTodo.title = parseResult.cleanTitle
        newTodo.orderIndex = Int64(todos.count)
        newTodo.scheduledDate = parseResult.suggestedDate
        do {
            try viewContext.save()
        } catch {
            Self.logger.error("Failed to save new todo: \(error.localizedDescription, privacy: .public)")
        }
        newTodoTitle = ""
        isAddingFocused = true
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func addTodoWithAI() async {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let trimmed = newTodoTitle.trimmed()
            guard !trimmed.isEmpty else { return }

            isParsingWithAI = true
            defer { isParsingWithAI = false }

            do {
                let parsed = try await TodoSmartParserService.parseTodo(from: trimmed)

                // Parse priority
                let priority: TodoPriority = {
                    switch parsed.priority.lowercased() {
                    case "high": return .high
                    case "medium": return .medium
                    case "low": return .low
                    default: return .none
                    }
                }()

                // Parse due date
                let dueDate: Date? = {
                    guard !parsed.dueDate.isEmpty else { return nil }
                        return DateFormatters.iso8601DateTime.date(from: parsed.dueDate)
                }()

                // Parse recurrence
                let recurrence: RecurrencePattern = {
                    switch parsed.recurrence.lowercased() {
                    case "daily": return .daily
                    case "weekdays": return .weekdays
                    case "weekly": return .weekly
                    case "biweekly": return .biweekly
                    case "monthly": return .monthly
                    case "yearly": return .yearly
                    default: return .none
                    }
                }()

                let newTodo = CDTodoItem(context: viewContext)
                newTodo.title = parsed.title.isEmpty ? trimmed : parsed.title
                newTodo.orderIndex = Int64(todos.count)
                newTodo.dueDate = dueDate
                newTodo.priority = priority
                newTodo.recurrence = recurrence
                do {
                    try viewContext.save()
                } catch {
                    Self.logger.error("Failed to save new todo: \(error.localizedDescription, privacy: .public)")
                }
                newTodoTitle = ""
                isAddingFocused = true
            } catch {
                // Fall back to simple add if AI parsing fails
                addTodo()
            }
        } else {
            addTodo()
        }
        #else
        addTodo()
        #endif
    }

    func toggleTodo(_ todo: CDTodoItem) {
        todo.isCompleted.toggle()
        if todo.isCompleted {
            todo.completedAt = Date()

            // Handle recurring todos
            if todo.recurrence != .none {
                let baseDate: Date
                let today = AppCalendar.startOfDay(Date())

                if todo.repeatAfterCompletion {
                    // "After completion" mode: calculate from today
                    baseDate = today
                } else {
                    baseDate = todo.dueDate ?? today
                }

                let nextDueDate: Date?
                if todo.recurrence == .custom, todo.customIntervalDays > 0 {
                    nextDueDate = Calendar.current.date(byAdding: .day, value: Int(todo.customIntervalDays), to: baseDate)
                } else {
                    nextDueDate = todo.recurrence.nextDate(after: baseDate)
                }

                if let nextDueDate {
                    // Preserve the scheduledDate offset if both were set
                    var nextScheduled: Date?
                    if let scheduled = todo.scheduledDate, let due = todo.dueDate {
                        let offset = Calendar.current.dateComponents([.day], from: due, to: scheduled).day ?? 0
                        nextScheduled = Calendar.current.date(byAdding: .day, value: offset, to: nextDueDate)
                    } else if todo.scheduledDate != nil {
                        nextScheduled = nextDueDate
                    }

                    let newTodo = CDTodoItem(context: viewContext)
                    newTodo.title = todo.title
                    newTodo.notes = todo.notes
                    newTodo.orderIndex = Int64(todos.count)
                    newTodo.studentIDs = todo.studentIDs
                    newTodo.dueDate = nextDueDate
                    newTodo.scheduledDate = nextScheduled
                    newTodo.priority = todo.priority
                    newTodo.recurrence = todo.recurrence
                    newTodo.repeatAfterCompletion = todo.repeatAfterCompletion
                    newTodo.customIntervalDays = todo.customIntervalDays
                    newTodo.tags = todo.tags
                }
            }
        } else {
            todo.completedAt = nil
        }
        do {
            try viewContext.save()
        } catch {
            Self.logger.error("Failed to save todo completion: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteTodo(_ todo: CDTodoItem) {
        viewContext.delete(todo)
        do {
            try viewContext.save()
        } catch {
            Self.logger.error("Failed to delete todo: \(error.localizedDescription, privacy: .public)")
        }
    }

    func moveTodos(from source: IndexSet, to destination: Int) {
        var reorderedTodos = Array(todos)
        reorderedTodos.move(fromOffsets: source, toOffset: destination)

        // Update orderIndex for all todos
        for (index, todo) in reorderedTodos.enumerated() {
            todo.orderIndex = Int64(index)
        }

        do {
            try viewContext.save()
        } catch {
            Self.logger.error("Failed to update todo order: \(error.localizedDescription, privacy: .public)")
        }
    }
}
