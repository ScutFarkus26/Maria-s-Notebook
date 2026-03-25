// TodoMainView+BatchOperations.swift
// Elegant full-screen todo list view inspired by Things and Bear

import OSLog
import SwiftUI
import SwiftData

extension TodoMainView {
    private static let logger = Logger.todos

    func batchComplete() {
        _ = adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todosToComplete = allTodos.filter { selectedTodoIDs.contains($0.id) }
            for todo in todosToComplete {
                todo.isCompleted = true
                todo.completedAt = Date()
            }
            do {
                try modelContext.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to batch complete: \(error)")
            }
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }

    func batchSetHighPriority() {
        _ = adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todos = allTodos.filter { selectedTodoIDs.contains($0.id) }
            for todo in todos {
                todo.priority = .high
            }
            do {
                try modelContext.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to batch set priority: \(error)")
            }
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }

    func batchSetDueToday() {
        _ = adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todos = allTodos.filter { selectedTodoIDs.contains($0.id) }
            let today = Calendar.current.startOfDay(for: Date())
            for todo in todos {
                todo.dueDate = today
            }
            do {
                try modelContext.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to batch set due date: \(error)")
            }
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }

    func batchDelete() {
        _ = adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todosToDelete = allTodos.filter { selectedTodoIDs.contains($0.id) }
            for todo in todosToDelete {
                modelContext.delete(todo)
            }
            do {
                try modelContext.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to batch delete: \(error)")
            }
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }
}
