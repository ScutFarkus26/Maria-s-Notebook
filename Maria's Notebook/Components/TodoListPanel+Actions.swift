import SwiftUI
import SwiftData

extension TodoListPanel {
    func addTodo() {
        let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parseResult = TodoDateParser.parse(trimmed)
        let newTodo = TodoItem(
            title: parseResult.cleanTitle,
            orderIndex: todos.count,
            scheduledDate: parseResult.suggestedDate
        )
        modelContext.insert(newTodo)
        do {
            try modelContext.save()
        } catch {
            print("\u{26A0}\u{FE0F} [\(#function)] Failed to save new todo: \(error)")
        }
        newTodoTitle = ""
        isAddingFocused = true
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func addTodoWithAI() async {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    let formatter = ISO8601DateFormatter()
                    return formatter.date(from: parsed.dueDate)
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

                let newTodo = TodoItem(
                    title: parsed.title.isEmpty ? trimmed : parsed.title,
                    orderIndex: todos.count,
                    dueDate: dueDate,
                    priority: priority,
                    recurrence: recurrence
                )

                modelContext.insert(newTodo)
                do {
                    try modelContext.save()
                } catch {
                    print("\u{26A0}\u{FE0F} [\(#function)] Failed to save new todo: \(error)")
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

    func toggleTodo(_ todo: TodoItem) {
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
                if todo.recurrence == .custom, let interval = todo.customIntervalDays {
                    nextDueDate = Calendar.current.date(byAdding: .day, value: interval, to: baseDate)
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

                    let newTodo = TodoItem(
                        title: todo.title,
                        notes: todo.notes,
                        orderIndex: todos.count,
                        studentIDs: todo.studentIDs,
                        dueDate: nextDueDate,
                        scheduledDate: nextScheduled,
                        priority: todo.priority,
                        recurrence: todo.recurrence
                    )
                    newTodo.repeatAfterCompletion = todo.repeatAfterCompletion
                    newTodo.customIntervalDays = todo.customIntervalDays
                    newTodo.tags = todo.tags
                    modelContext.insert(newTodo)
                }
            }
        } else {
            todo.completedAt = nil
        }
        do {
            try modelContext.save()
        } catch {
            print("\u{26A0}\u{FE0F} [\(#function)] Failed to save todo completion: \(error)")
        }
    }

    func deleteTodo(_ todo: TodoItem) {
        modelContext.delete(todo)
        do {
            try modelContext.save()
        } catch {
            print("\u{26A0}\u{FE0F} [\(#function)] Failed to delete todo: \(error)")
        }
    }

    func moveTodos(from source: IndexSet, to destination: Int) {
        var reorderedTodos = todos
        reorderedTodos.move(fromOffsets: source, toOffset: destination)

        // Update orderIndex for all todos
        for (index, todo) in reorderedTodos.enumerated() {
            todo.orderIndex = index
        }

        do {
            try modelContext.save()
        } catch {
            print("\u{26A0}\u{FE0F} [\(#function)] Failed to update todo order: \(error)")
        }
    }
}
