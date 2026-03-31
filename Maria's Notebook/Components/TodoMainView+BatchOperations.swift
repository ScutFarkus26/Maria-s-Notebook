// TodoMainView+BatchOperations.swift
// Elegant full-screen todo list view inspired by Things and Bear

import OSLog
import SwiftUI
import CoreData

extension TodoMainView {
    private static let logger = Logger.todos

    func batchComplete() {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todosToComplete = allTodos.filter { $0.id.map { selectedTodoIDs.contains($0) } ?? false }
            for todo in todosToComplete {
                todo.isCompleted = true
                todo.completedAt = Date()
            }
            do {
                try viewContext.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to batch complete: \(error)")
            }
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
            do {
                try viewContext.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to batch set priority: \(error)")
            }
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }

    func batchSetDueToday() {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todos = allTodos.filter { $0.id.map { selectedTodoIDs.contains($0) } ?? false }
            let today = Calendar.current.startOfDay(for: Date())
            for todo in todos {
                todo.dueDate = today
            }
            do {
                try viewContext.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to batch set due date: \(error)")
            }
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
            do {
                try viewContext.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to batch delete: \(error)")
            }
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }
}
