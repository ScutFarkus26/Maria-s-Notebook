// TodayViewTodoSection.swift
// Todo section for TodayView - extracted for maintainability

import SwiftUI
import CoreData

// MARK: - TodayView Todo Section Extension

extension TodayView {

    // MARK: - Todos Section (Things-inspired "Today" section)

    /// Pre-partitioned todos for the selected day, computed once per body evaluation.
    struct TodosPartition {
        let all: [CDTodoItem]
        let overdue: [CDTodoItem]
        let dueOnDay: [CDTodoItem]
        let highPriority: [CDTodoItem]
    }

    private var todosPartition: TodosPartition {
        let selectedDay = AppCalendar.startOfDay(viewModel.date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        let todos = todayTodos

        let overdue = todos.filter { todo in
            guard let dueDate = todo.dueDate else { return false }
            return dueDate < selectedDay && (todo.scheduledDate == nil || todo.scheduledDate! < nextDay)
        }
        let dueOnDay = todos.filter { todo in
            let isOverdue = todo.dueDate.map {
                $0 < selectedDay && (todo.scheduledDate == nil || todo.scheduledDate! < nextDay)
            } ?? false
            guard !isOverdue else { return false }
            if let scheduled = todo.scheduledDate,
               scheduled >= selectedDay && scheduled < nextDay { return true }
            if let dueDate = todo.dueDate,
               dueDate >= selectedDay && dueDate < nextDay { return true }
            return false
        }
        let overdueIDs = Set(overdue.map(\.id))
        let dueOnDayIDs = Set(dueOnDay.map(\.id))
        let highPriority = todos.filter { todo in
            !overdueIDs.contains(todo.id) && !dueOnDayIDs.contains(todo.id)
        }
        return TodosPartition(all: todos, overdue: overdue, dueOnDay: dueOnDay, highPriority: highPriority)
    }

    var todosListSection: some View {
        let partition = todosPartition
        return Section {
            todosSectionContent(partition)
        } header: {
            todosSectionHeader(count: partition.all.count)
        }
    }

    @ViewBuilder
    private func todosSectionContent(_ partition: TodosPartition) -> some View {
        if partition.all.isEmpty {
            emptyStateText("No todos for today")
        } else {
            todosOverdueGroup(partition)
            todosDueOnDayGroup(partition)
            todosHighPriorityGroup(partition)
        }
    }

    @ViewBuilder
    private func todosOverdueGroup(_ partition: TodosPartition) -> some View {
        if !partition.overdue.isEmpty {
            overdueSubheader
            ForEach(partition.overdue) { todo in
                overdueTodoRow(todo)
            }
        }
    }

    @ViewBuilder
    private func todosDueOnDayGroup(_ partition: TodosPartition) -> some View {
        if !partition.dueOnDay.isEmpty {
            if !partition.overdue.isEmpty {
                tertiarySubheader("Today")
            }
            ForEach(partition.dueOnDay) { todo in
                completableTodoRow(todo)
            }
        }
    }

    @ViewBuilder
    private func todosHighPriorityGroup(_ partition: TodosPartition) -> some View {
        if !partition.highPriority.isEmpty {
            if !partition.overdue.isEmpty || !partition.dueOnDay.isEmpty {
                tertiarySubheader("High Priority")
            }
            ForEach(partition.highPriority) { todo in
                completableTodoRow(todo)
            }
        }
    }

    private var overdueSubheader: some View {
        Text("Overdue")
            .font(AppTheme.ScaledFont.caption)
            .foregroundStyle(.red.opacity(UIConstants.OpacityConstants.heavy))
            .textCase(.uppercase)
            .tracking(0.5)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
    }

    private func tertiarySubheader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.ScaledFont.caption)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
    }

    private func overdueTodoRow(_ todo: CDTodoItem) -> some View {
        TodoTodayRow(todo: todo, onToggle: { toggleTodoItem(todo) }, onTap: { selectedTodoItem = todo })
            .id(todo.id)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            .swipeActions(edge: .leading) {
                Button {
                    toggleTodoItem(todo)
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button {
                    selectedTodoItem = todo
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
    }

    private func completableTodoRow(_ todo: CDTodoItem) -> some View {
        TodoTodayRow(todo: todo, onToggle: { toggleTodoItem(todo) }, onTap: { selectedTodoItem = todo })
            .id(todo.id)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            .swipeActions(edge: .leading) {
                Button {
                    toggleTodoItem(todo)
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.green)
            }
    }

    @ViewBuilder
    func todosSectionHeader(count: Int) -> some View {
        HStack {
            Text("Todos")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
            }
            Button {
                isShowingNewTodo = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
    }

    /// Todos relevant to the selected day: scheduled for day, overdue deadline, due on date, or high priority.
    /// Someday todos are excluded.
    var todayTodos: [CDTodoItem] {
        let selectedDay = AppCalendar.startOfDay(viewModel.date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay

        return todayTodoItems.filter { todo in
            guard !todo.isCompleted else { return false }
            // Exclude someday items
            guard !todo.isSomeday else { return false }

            // Scheduled for the selected date
            if let scheduled = todo.scheduledDate, scheduled >= selectedDay && scheduled < nextDay {
                return true
            }
            // Overdue deadline relative to the selected date
            if let dueDate = todo.dueDate, dueDate < selectedDay {
                // Only show overdue if not scheduled for a future date
                if let scheduled = todo.scheduledDate, scheduled >= nextDay {
                    return false
                }
                return true
            }
            // Deadline on the selected date (and not scheduled for a different day)
            if let dueDate = todo.dueDate, dueDate >= selectedDay && dueDate < nextDay {
                return true
            }
            // High priority (always shown)
            if todo.priority == .high {
                return true
            }
            return false
        }
        .sorted { lhs, rhs in
            let lhsOverdue = lhs.dueDate.map { $0 < selectedDay } ?? false
            let rhsOverdue = rhs.dueDate.map { $0 < selectedDay } ?? false
            let lhsScheduled = lhs.scheduledDate.map { $0 >= selectedDay && $0 < nextDay } ?? false
            let rhsScheduled = rhs.scheduledDate.map { $0 >= selectedDay && $0 < nextDay } ?? false
            let lhsDueOnDay = lhs.dueDate.map { $0 >= selectedDay && $0 < nextDay } ?? false
            let rhsDueOnDay = rhs.dueDate.map { $0 >= selectedDay && $0 < nextDay } ?? false

            // Overdue first, then scheduled for today, then due on selected day, then high priority
            if lhsOverdue != rhsOverdue { return lhsOverdue }
            if lhsScheduled != rhsScheduled { return lhsScheduled }
            if lhsDueOnDay != rhsDueOnDay { return lhsDueOnDay }
            return lhs.priority.sortOrder < rhs.priority.sortOrder
        }
    }
}
