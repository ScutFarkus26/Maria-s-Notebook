// TodayViewTodoSection.swift
// Todo section for TodayView - extracted for maintainability

import SwiftUI
import SwiftData

// MARK: - TodayView Todo Section Extension

extension TodayView {

    // MARK: - Todos Section (Things-inspired "Today" section)

    var todosListSection: some View {
        let selectedDay = AppCalendar.startOfDay(viewModel.date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay

        return Section {
            if todayTodos.isEmpty {
                emptyStateText("No todos for today")
            } else {
                // Overdue todos (deadline before the selected day)
                let overdue = todayTodos.filter { todo in
                    guard let dueDate = todo.dueDate else { return false }
                    return dueDate < selectedDay && (todo.scheduledDate == nil || todo.scheduledDate! < nextDay)
                }
                if !overdue.isEmpty {
                    Text("Overdue")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    ForEach(overdue) { todo in
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
                }
                // Scheduled or due on selected day
                let dueOnDay = todayTodos.filter { todo in
                    let isOverdue = todo.dueDate.map { $0 < selectedDay && (todo.scheduledDate == nil || todo.scheduledDate! < nextDay) } ?? false
                    guard !isOverdue else { return false }
                    if let scheduled = todo.scheduledDate, scheduled >= selectedDay && scheduled < nextDay { return true }
                    if let dueDate = todo.dueDate, dueDate >= selectedDay && dueDate < nextDay { return true }
                    return false
                }
                if !dueOnDay.isEmpty {
                    if !overdue.isEmpty {
                        Text("Today")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    }
                    ForEach(dueOnDay) { todo in
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
                }
                // High priority without a date on the selected day
                let overdueIDs = Set(overdue.map(\.id))
                let dueOnDayIDs = Set(dueOnDay.map(\.id))
                let highPriority = todayTodos.filter { todo in
                    !overdueIDs.contains(todo.id) && !dueOnDayIDs.contains(todo.id)
                }
                if !highPriority.isEmpty {
                    if !overdue.isEmpty || !dueOnDay.isEmpty {
                        Text("High Priority")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    }
                    ForEach(highPriority) { todo in
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
                }
            }
        } header: {
            todosSectionHeader
        }
    }

    @ViewBuilder
    var todosSectionHeader: some View {
        HStack {
            Text("Todos")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            let count = todayTodos.count
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
    var todayTodos: [TodoItem] {
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
