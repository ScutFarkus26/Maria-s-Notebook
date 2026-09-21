// TodoMainView+BatchOperations.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import CoreData

extension TodoMainView {
    func batchComplete() {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todosToComplete = allTodos.filter { $0.id.map { selectedTodoIDs.contains($0) } ?? false }
            for todo in todosToComplete {
                todo.isCompleted = true
                todo.completedAt = Date()
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

    func batchSetDueToday() {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todos = allTodos.filter { $0.id.map { selectedTodoIDs.contains($0) } ?? false }
            let today = AppCalendar.shared.startOfDay(for: Date())
            for todo in todos {
                todo.dueDate = today
            }
            dependencies.saveCoordinator.save(viewContext, reason: "Set todos due today")
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
