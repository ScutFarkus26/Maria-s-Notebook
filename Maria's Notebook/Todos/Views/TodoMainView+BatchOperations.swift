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
            viewContext.safeSave()
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
            viewContext.safeSave()
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
            viewContext.safeSave()
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
            viewContext.safeSave()
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }
}
