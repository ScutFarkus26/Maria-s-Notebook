// TodoMainView+BatchOperations.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import CoreData

extension TodoMainView {
    /// The to-dos picked in Select mode, by id.
    var selectedTodoIDs: Set<UUID> {
        get { batchSelection.ids }
        nonmutating set { batchSelection.ids = newValue }
    }

    /// The list the screen shows: the sidebar pick and the search text.
    var listScope: TodoListScope {
        TodoListScope(
            filter: selectedFilter, tag: selectedTag, folder: selectedFolder,
            tideList: selectedTideList, searchText: searchText
        )
    }

    /// "Delete 3 completed to-dos?", "Delete 1 to-do?"
    static func deleteQuestion(count: Int, completed: Bool) -> String {
        let noun = count == 1 ? "to-do" : "to-dos"
        return completed ? "Delete \(count) completed \(noun)?" : "Delete \(count) \(noun)?"
    }

    /// Shows a confirmation while `count` holds the number it asks about.
    func isAsking(_ count: Binding<Int?>) -> Binding<Bool> {
        Binding(get: { count.wrappedValue != nil }, set: { if !$0 { count.wrappedValue = nil } })
    }

    /// Completes the selected open todos through `TodoCompletionService`, so
    /// each repeating one gets its next occurrence. Ones already done stay as
    /// they are.
    func batchComplete() {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todosToComplete = batchSelection.selected(in: filteredTodos)
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
            let todos = batchSelection.selected(in: filteredTodos)
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
            let todos = batchSelection.selected(in: filteredTodos)
            TodoScheduling.moveToToday(todos)
            dependencies.saveCoordinator.save(viewContext, reason: "Move todos to today")
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }

    func batchDelete() {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            let todosToDelete = batchSelection.selected(in: filteredTodos)
            for todo in todosToDelete {
                viewContext.delete(todo)
            }
            dependencies.saveCoordinator.save(viewContext, reason: "Delete todos")
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }

    // MARK: - New Todo Sheet

    var newTodoSheet: some View {
        NavigationStack {
            NewTodoForm()
                .navigationTitle("New Todo")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isShowingNewTodo = false
                        }
                    }
                }
        }
    }
}
