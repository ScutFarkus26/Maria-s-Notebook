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

    /// Due work check-ins split the way the todos are, computed once per body.
    struct FollowUpPartition {
        let overdue: [WorkCheckInFollowUp]
        let dueOnDay: [WorkCheckInFollowUp]

        var isEmpty: Bool { overdue.isEmpty && dueOnDay.isEmpty }
        var count: Int { overdue.count + dueOnDay.count }
    }

    private var followUpPartition: FollowUpPartition {
        let rows = viewModel.followUpCheckIns
        return FollowUpPartition(
            overdue: rows.filter(\.isOverdue),
            dueOnDay: rows.filter { !$0.isOverdue }
        )
    }

    /// The todo section owns its own todo fetch, so a todo edit re-renders
    /// this section instead of the whole Today screen.
    var todosListSection: some View {
        TodayTodosSectionView(
            date: viewModel.date,
            followUps: followUpPartition,
            hiddenTodoIDs: viewModel.linkedTodos.hiddenTodoIDs,
            studentShortNames: dependencies.roster.shortNamesByFullName,
            onToggle: { toggleTodoItem($0) },
            onOpen: { selectedTodoItem = $0 },
            onNewTodo: { activeSheet = .newTodo },
            followUpRow: { checkInFollowUpRow($0) }
        )
    }
}

// MARK: - Todos Section View

/// Today's todo list: open todos scheduled or due on the selected day, overdue,
/// or high priority, interleaved with the due work check-ins the parent passes in.
/// A todo linked to work with a row on Today is left out (`hiddenTodoIDs`):
/// that row shows it ("3 todos · Sep 18"), so it is not listed twice.
struct TodayTodosSectionView<FollowUpRow: View>: View {
    typealias TodosPartition = TodayView.TodosPartition
    typealias FollowUpPartition = TodayView.FollowUpPartition

    let date: Date
    let followUps: FollowUpPartition
    /// Linked todos whose work row is on Today (`TodayLinkedTodos.hiddenTodoIDs`).
    let hiddenTodoIDs: Set<UUID>
    /// The roster's short names by full name, for student tag chips.
    let studentShortNames: [String: String]
    let onToggle: (CDTodoItem) -> Void
    let onOpen: (CDTodoItem) -> Void
    let onNewTodo: () -> Void
    @ViewBuilder let followUpRow: (WorkCheckInFollowUp) -> FollowUpRow

    @Environment(\.calendar) private var calendar

    /// Narrowed by `fetchPredicate` (it used to be every open todo); `isShown`
    /// still makes the exact call in `partition`.
    @FetchRequest private var todoItems: FetchedResults<CDTodoItem>

    init(
        date: Date,
        followUps: FollowUpPartition,
        hiddenTodoIDs: Set<UUID>,
        studentShortNames: [String: String],
        onToggle: @escaping (CDTodoItem) -> Void,
        onOpen: @escaping (CDTodoItem) -> Void,
        onNewTodo: @escaping () -> Void,
        @ViewBuilder followUpRow: @escaping (WorkCheckInFollowUp) -> FollowUpRow
    ) {
        self.date = date
        self.followUps = followUps
        self.hiddenTodoIDs = hiddenTodoIDs
        self.studentShortNames = studentShortNames
        self.onToggle = onToggle
        self.onOpen = onOpen
        self.onNewTodo = onNewTodo
        self.followUpRow = followUpRow
        _todoItems = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: false)],
            predicate: Self.fetchPredicate(selectedDay: AppCalendar.startOfDay(date))
        )
    }

    /// The store's half of `isShown`, wide enough to never drop a todo it
    /// shows: open, not someday, and high priority or due or scheduled
    /// before a horizon two days past the selected day. Every shown todo
    /// passes — one scheduled or due on the day, or overdue, is dated before
    /// the next day, which the environment calendar puts at most 25 hours
    /// on — while undated and future todos below high priority stay in the store.
    static func fetchPredicate(selectedDay: Date) -> NSPredicate {
        let horizon = selectedDay.addingTimeInterval(2 * 24 * 3600) as NSDate
        return NSPredicate(
            format: "isCompleted == NO AND isSomeday == NO "
                + "AND (priorityRaw == %@ OR dueDate < %@ OR scheduledDate < %@)",
            TodoPriority.high.rawValue, horizon, horizon
        )
    }

    var body: some View {
        let partition = Self.partition(Array(todoItems), date: date, calendar: calendar, hiding: hiddenTodoIDs)
        let count = partition.all.count + followUps.count
        if TodaySectionVisibility.showsTodos(count: count) {
            Section {
                todosSectionContent(partition, followUps)
            } header: {
                todosSectionHeader(count: count)
            }
        }
    }

    /// Open, not someday, and scheduled or due on the day, overdue (unless
    /// rescheduled past it), or high priority.
    private static func isShown(_ todo: CDTodoItem, selectedDay: Date, nextDay: Date) -> Bool {
        guard !todo.isCompleted else { return false }
        guard !todo.isSomeday else { return false }
        if let scheduled = todo.scheduledDate, scheduled >= selectedDay && scheduled < nextDay { return true }
        if let dueDate = todo.dueDate, dueDate < selectedDay {
            if let scheduled = todo.scheduledDate, scheduled >= nextDay { return false }
            return true
        }
        if let dueDate = todo.dueDate, dueDate >= selectedDay && dueDate < nextDay { return true }
        return todo.priority == .high
    }

    /// Overdue first, then scheduled on the day, then due on the day, then by priority.
    private static func precedes(_ lhs: CDTodoItem, _ rhs: CDTodoItem, selectedDay: Date, nextDay: Date) -> Bool {
        let lhsOverdue: Bool = lhs.dueDate.map { $0 < selectedDay } ?? false
        let rhsOverdue: Bool = rhs.dueDate.map { $0 < selectedDay } ?? false
        if lhsOverdue != rhsOverdue { return lhsOverdue }
        let lhsScheduled: Bool = lhs.scheduledDate.map { $0 >= selectedDay && $0 < nextDay } ?? false
        let rhsScheduled: Bool = rhs.scheduledDate.map { $0 >= selectedDay && $0 < nextDay } ?? false
        if lhsScheduled != rhsScheduled { return lhsScheduled }
        let lhsDueOnDay: Bool = lhs.dueDate.map { $0 >= selectedDay && $0 < nextDay } ?? false
        let rhsDueOnDay: Bool = rhs.dueDate.map { $0 >= selectedDay && $0 < nextDay } ?? false
        if lhsDueOnDay != rhsDueOnDay { return lhsDueOnDay }
        return lhs.priority.sortOrder < rhs.priority.sortOrder
    }

    static func partition(
        _ todoItems: [CDTodoItem], date: Date, calendar: Calendar, hiding hidden: Set<UUID> = []
    ) -> TodosPartition {
        // Compute date boundaries once — todayTodos and the partition sub-filters all need them.
        let selectedDay = AppCalendar.startOfDay(date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay

        // Filter and sort the raw fetch results in a single pass.
        let todos = todoItems
            .filter { todo in
                !(todo.id.map(hidden.contains) ?? false)
                    && isShown(todo, selectedDay: selectedDay, nextDay: nextDay)
            }
            .sorted { precedes($0, $1, selectedDay: selectedDay, nextDay: nextDay) }

        // Partition the already-sorted list — reuses the pre-computed dates.
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

    @ViewBuilder
    private func todosSectionContent(_ partition: TodosPartition, _ followUps: FollowUpPartition) -> some View {
        if partition.all.isEmpty && followUps.isEmpty {
            TodayView.emptyStateLabel("No todos for today")
        } else {
            todosOverdueGroup(partition, followUps)
            todosDueOnDayGroup(partition, followUps)
            todosHighPriorityGroup(partition, followUps)
        }
    }

    @ViewBuilder
    private func todosOverdueGroup(_ partition: TodosPartition, _ followUps: FollowUpPartition) -> some View {
        if !partition.overdue.isEmpty || !followUps.overdue.isEmpty {
            overdueSubheader
            ForEach(partition.overdue) { todo in
                overdueTodoRow(todo)
            }
            overdueFollowUpRows(followUps)
        }
    }

    @ViewBuilder
    private func overdueFollowUpRows(_ followUps: FollowUpPartition) -> some View {
        ForEach(followUps.overdue) { item in
            followUpRow(item)
        }
    }

    @ViewBuilder
    private func todosDueOnDayGroup(_ partition: TodosPartition, _ followUps: FollowUpPartition) -> some View {
        if !partition.dueOnDay.isEmpty || !followUps.dueOnDay.isEmpty {
            if !partition.overdue.isEmpty || !followUps.overdue.isEmpty {
                tertiarySubheader("Today")
            }
            ForEach(partition.dueOnDay) { todo in
                completableTodoRow(todo)
            }
            dueOnDayFollowUpRows(followUps)
        }
    }

    @ViewBuilder
    private func dueOnDayFollowUpRows(_ followUps: FollowUpPartition) -> some View {
        ForEach(followUps.dueOnDay) { item in
            followUpRow(item)
        }
    }

    @ViewBuilder
    private func todosHighPriorityGroup(_ partition: TodosPartition, _ followUps: FollowUpPartition) -> some View {
        if !partition.highPriority.isEmpty {
            if !partition.overdue.isEmpty || !partition.dueOnDay.isEmpty || !followUps.isEmpty {
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

    private func todoRow(_ todo: CDTodoItem) -> some View {
        TodoTodayRow(
            todo: todo,
            studentShortNames: studentShortNames,
            onToggle: { onToggle(todo) },
            onTap: { onOpen(todo) }
        )
        .id(todo.id)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
    }

    /// A completable row, plus Edit on the trailing swipe.
    private func overdueTodoRow(_ todo: CDTodoItem) -> some View {
        completableTodoRow(todo)
            .swipeActions(edge: .trailing) {
                Button {
                    onOpen(todo)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
    }

    private func completableTodoRow(_ todo: CDTodoItem) -> some View {
        todoRow(todo)
            .swipeActions(edge: .leading) {
                Button {
                    onToggle(todo)
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.green)
            }
    }

    @ViewBuilder
    private func todosSectionHeader(count: Int) -> some View {
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
                    .capsuleFill(Color.accentColor)
            }
            Button {
                onNewTodo()
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
    }

}
