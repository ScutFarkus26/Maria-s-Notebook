// TodoMainView+BatchOperations.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import CoreData

extension TodoMainView {
    /// Completes the selected open todos through `TodoCompletionService`, so
    /// each repeating one gets its next occurrence. Ones already done stay as
    /// they are.
    func batchComplete() {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todosToComplete = allTodos.filter { $0.id.map { selectedTodoIDs.contains($0) } ?? false }
            for todo in todosToComplete where !todo.isCompleted {
                TodoCompletionService.complete(todo)
            }
            dependencies.saveCoordinator.save(viewContext, reason: "Complete todos")
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }

    func batchSetHighPriority() {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todos = allTodos.filter { $0.id.map { selectedTodoIDs.contains($0) } ?? false }
            for todo in todos {
                todo.priority = .high
            }
            dependencies.saveCoordinator.save(viewContext, reason: "Set todo priority")
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }

    /// Plans the selected todos for today, as the row's Today swipe does;
    /// their deadlines stay as they are.
    func batchMoveToToday() {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todos = allTodos.filter { $0.id.map { selectedTodoIDs.contains($0) } ?? false }
            TodoScheduling.moveToToday(todos)
            dependencies.saveCoordinator.save(viewContext, reason: "Move todos to today")
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }

    func batchDelete() {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todosToDelete = allTodos.filter { $0.id.map { selectedTodoIDs.contains($0) } ?? false }
            for todo in todosToDelete {
                viewContext.delete(todo)
            }
            dependencies.saveCoordinator.save(viewContext, reason: "Delete todos")
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }
}
