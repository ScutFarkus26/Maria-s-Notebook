// TodoMainView+ContentArea.swift
// Main content area for the todo list

import SwiftUI
import CoreData

extension TodoMainView {
    // MARK: - Todo List Content

    var todoListContent: some View {
        VStack(spacing: 0) {
            // Select mode header
            if isSelectMode {
                HStack {
                    Button {
                        if selectedTodoIDs.count == filteredTodos.count {
                            selectedTodoIDs.removeAll()
                        } else {
                            selectedTodoIDs = Set(filteredTodos.compactMap(\.id))
                        }
                    } label: {
                        Text(selectedTodoIDs.count == filteredTodos.count ? "Deselect All" : "Select All")
                            .font(AppTheme.ScaledFont.bodySemibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.accent)

                    Spacer()

                    Text("\(selectedTodoIDs.count) selected")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Search bar
            searchBar
                .padding(.horizontal, 20)
                .padding(.top, isSelectMode ? 4 : 16)
                .padding(.bottom, 12)

            if filteredTodos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedSectionKeys, id: \.self) { section in
                            if let todos = groupedTodos[section], !todos.isEmpty {
                                todoSection(title: section, todos: todos)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, isSelectMode ? 100 : 40)
                }
            }

            // Batch action bar
            if isSelectMode && !selectedTodoIDs.isEmpty {
                batchActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .navigationTitle(
            selectedTideList.map(TideActionLink.listName(ofFile:))
                ?? selectedFolder
                ?? (selectedTag != nil
                    ? TodoTagHelper.tagName(selectedTag!)
                    : (selectedFilter ?? .inbox).title)
        )
    }

    // MARK: - Batch Action Bar

    var batchActionBar: some View {
        HStack(spacing: 0) {
            batchButton(title: "Complete", icon: "checkmark.circle", color: .green) {
                batchComplete()
            }

            Divider().frame(height: 30)

            batchButton(title: "Priority", icon: "flag", color: .orange) {
                batchSetHighPriority()
            }

            Divider().frame(height: 30)

            batchButton(title: "Today", icon: "calendar", color: .blue) {
                batchMoveToToday()
            }

            Divider().frame(height: 30)

            batchButton(title: "Delete", icon: "trash", color: .red) {
                // Asks first, with the count (bug hunt 2026-11-03, #51).
                let count = batchSelection.selected(in: filteredTodos).count
                if count > 0 { pendingBatchDeleteCount = count }
            }
        }
        .padding(.vertical, 8)
        #if os(iOS)
        .background(.ultraThinMaterial)
        #else
        .background(.regularMaterial)
        #endif
        .clipRounded(UIConstants.CornerRadius.extraLarge)
        .shadow(color: .black.opacity(UIConstants.OpacityConstants.accent), radius: 8, y: 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    func batchButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.system(size: 14))

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(AppTheme.ScaledFont.body)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        .clipShape(Capsule(style: .continuous))
    }

    // MARK: - Grouped Todos

    var groupedTodos: [String: [CDTodoItem]] {
        var groups: [String: [CDTodoItem]] = [:]
        let today = calendarDay
        for todo in filteredTodos {
            let section = Self.sectionTitle(for: todo, filter: selectedFilter, today: today)
            groups[section, default: []].append(todo)
        }
        return groups
    }

    /// The heading `todo` is listed under in `filter` on the day `today`
    /// falls on: Overdue, Today, Tomorrow, an Upcoming day, Later, Upcoming,
    /// Anytime, Someday or Completed.
    static func sectionTitle(
        for todo: CDTodoItem, filter: TodoListFilter?, today: Date, calendar: Calendar = AppCalendar.shared
    ) -> String {
        let startOfToday = calendar.startOfDay(for: today)
        let tomorrow = AppCalendar.addingDays(1, to: startOfToday)
        // For Upcoming filter, use day-by-day timeline
        let useDayTimeline = filter == .upcoming

        if filter == .completed { return "Completed" }
        if filter == .someday { return "Someday" }
        if todo.isCompleted { return "Completed" }
        guard var effective = todo.effectiveDate else {
            return todo.isSomeday ? "Someday" : "Anytime"
        }
        // A deadline that has come is what puts it in Today, so it decides
        // the heading even when the todo is planned for a later day (bug hunt
        // 2026-11-03, #58).
        if let due = todo.dueDate, due < tomorrow { effective = min(effective, due) }
        if let due = todo.dueDate, due < startOfToday { return "Overdue" }
        if calendar.isDate(effective, inSameDayAs: startOfToday) { return "Today" }
        if calendar.isDate(effective, inSameDayAs: tomorrow) {
            return useDayTimeline ? upcomingDayKey(effective) : "Tomorrow"
        }
        if effective < startOfToday { return "Overdue" }
        guard useDayTimeline else { return "Upcoming" }
        // Day-by-day grouping for upcoming timeline
        let daysAhead = calendar.dateComponents([.day], from: startOfToday, to: effective).day ?? 0
        return daysAhead <= 28 ? upcomingDayKey(effective) : "Later"
    }

    /// Sorted section keys for display order in the grouped todos view.
    var sortedSectionKeys: [String] {
        let keys = groupedTodos.keys
        let order = ["Overdue", "Today", "Tomorrow"]

        var sorted: [String] = []
        // Add known sections first in order
        for key in order where keys.contains(key) {
            sorted.append(key)
        }
        // Add day-timeline keys sorted by date
        let today = calendarDay
        let dayKeys = keys.filter { $0.contains(",") }.sorted { a, b in
            Self.upcomingDayDate(a, today: today) ?? .distantFuture
                < Self.upcomingDayDate(b, today: today) ?? .distantFuture
        }
        sorted.append(contentsOf: dayKeys)
        // Add remaining keys
        let remaining = ["Upcoming", "Anytime", "Someday", "Later", "Completed"]
        for key in remaining where keys.contains(key) {
            sorted.append(key)
        }
        return sorted
    }

    // swiftlint:disable:next function_body_length
    func todoSection(title: String, todos: [CDTodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Things-style section header
            HStack(spacing: 10) {
                sectionIcon(for: title)
                    .frame(width: 26, height: 26)

                Text(title)
                    .font(AppTheme.ScaledFont.bodyBold)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(todos.count)")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 20)
            .padding(.bottom, 10)

            // Todo rows with thin dividers
            VStack(spacing: 0) {
                ForEach(Array(todos.enumerated()), id: \.element.objectID) { index, todo in
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            if isSelectMode {
                                Button {
                                    toggleSelection(todo)
                                } label: {
                                    let isSelected = todo.id.map { selectedTodoIDs.contains($0) } ?? false
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 12)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }

                            TodoRowCard(todo: todo, onSelect: {
                                if isSelectMode {
                                    toggleSelection(todo)
                                } else {
                                    selectedTodo = todo
                                }
                            }, onEdit: {
                                selectedTodo = todo
                            }, onDelete: {
                                deleteTodo(todo)
                            })
                        }

                        if index < todos.count - 1 {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
            }
            .background(AppTheme.Colors.controlBackground)
            .clipRounded(UIConstants.CornerRadius.large, style: .continuous)
        }
    }

    @ViewBuilder
    func sectionIcon(for title: String) -> some View {
        let config = sectionIconConfig(for: title)
        Image(systemName: config.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(config.color)
            .frame(width: 26, height: 26)
            .background(
                config.color.opacity(UIConstants.OpacityConstants.accent),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }

    func sectionIconConfig(for title: String) -> (icon: String, color: Color) {
        switch title {
        case "Overdue": return ("exclamationmark.triangle.fill", .red)
        case "Today": return ("star.fill", .orange)
        case "Tomorrow": return ("sunrise.fill", .orange)
        case "Upcoming": return ("calendar", .purple)
        case "Anytime": return ("tray.fill", .blue)
        case "Someday": return ("moon.zzz.fill", .mint)
        case "Later": return ("calendar.badge.clock", .secondary)
        case "Completed": return ("checkmark.circle.fill", .green)
        default: return ("calendar", .secondary)
        }
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 20) {
            if selectedFolder != nil {
                Image(systemName: "folder")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(.quaternary)
            } else if let tag = selectedTag {
                Circle()
                    .fill(TodoTagHelper.tagColor(tag).color.opacity(UIConstants.OpacityConstants.medium))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "tag")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(TodoTagHelper.tagColor(tag).color.opacity(0.6))
                    }
            } else {
                let filter = selectedFilter ?? .inbox
                Image(systemName: filter.icon)
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(filter.color.opacity(UIConstants.OpacityConstants.quarter))
            }

            VStack(spacing: 6) {
                Text(emptyStateMessage)
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(.secondary)

                if selectedTag == nil && selectedFolder == nil && (selectedFilter == .inbox || selectedFilter == .all) {
                    Self.newTaskHint
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(60)
    }

    var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "No todos found"
        }
        if let list = selectedTideList {
            return "No todos from Tide's \(TideActionLink.listName(ofFile: list)) list"
        }
        if let folder = selectedFolder {
            return "No todos in \"\(folder)\""
        }
        if let tag = selectedTag {
            return "No todos tagged \"\(TodoTagHelper.tagName(tag))\""
        }
        return (selectedFilter ?? .inbox).emptyMessage
    }
}
