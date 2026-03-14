// TodoMainView+ContentArea.swift
// Main content area for the todo list

import SwiftUI
import SwiftData

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
                            selectedTodoIDs = Set(filteredTodos.map(\.id))
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
            selectedFolder
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
                batchSetDueToday()
            }

            Divider().frame(height: 30)

            batchButton(title: "Delete", icon: "trash", color: .red) {
                batchDelete()
            }
        }
        .padding(.vertical, 8)
        #if os(iOS)
        .background(.ultraThinMaterial)
        #else
        .background(.regularMaterial)
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
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

    var groupedTodos: [String: [TodoItem]] {
        var groups: [String: [TodoItem]] = [:]
        let cal = Calendar.current
        let today = AppCalendar.startOfDay(Date())

        // For Upcoming filter, use day-by-day timeline
        let useDayTimeline = selectedFilter == .upcoming

        for todo in filteredTodos {
            let section: String

            if selectedFilter == .completed {
                section = "Completed"
            } else if selectedFilter == .someday {
                section = "Someday"
            } else if let effective = todo.effectiveDate {
                if todo.isOverdue {
                    section = "Overdue"
                } else if cal.isDateInToday(effective) {
                    section = "Today"
                } else if cal.isDateInTomorrow(effective) {
                    section = useDayTimeline ? dayTimelineKey(effective) : "Tomorrow"
                } else if effective < today {
                    section = "Overdue"
                } else if useDayTimeline {
                    // Day-by-day grouping for upcoming timeline
                    let weeksAhead = cal.dateComponents([.day], from: today, to: effective).day ?? 0
                    if weeksAhead <= 28 {
                        section = dayTimelineKey(effective)
                    } else {
                        section = "Later"
                    }
                } else {
                    section = "Upcoming"
                }
            } else if todo.isSomeday {
                section = "Someday"
            } else {
                section = "Anytime"
            }

            if groups[section] == nil {
                groups[section] = []
            }
            groups[section]?.append(todo)
        }

        return groups
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
        let dayKeys = keys.filter { $0.contains(",") }.sorted { a, b in
            // Parse "EEE, MMM d" format for sorting
            dayTimelineDate(a) ?? .distantFuture < dayTimelineDate(b) ?? .distantFuture
        }
        sorted.append(contentsOf: dayKeys)
        // Add remaining keys
        let remaining = ["Upcoming", "Anytime", "Someday", "Later", "Completed"]
        for key in remaining where keys.contains(key) {
            sorted.append(key)
        }
        return sorted
    }

    // PERF: Static cached DateFormatter to avoid allocating per call.
    // DateFormatter is expensive to create; called once per todo during grouping.
    private static let dayTimelineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    func dayTimelineKey(_ date: Date) -> String {
        Self.dayTimelineFormatter.string(from: date)
    }

    func dayTimelineDate(_ key: String) -> Date? {
        Self.dayTimelineFormatter.defaultDate = AppCalendar.startOfDay(Date())
        return Self.dayTimelineFormatter.date(from: key)
    }

    // swiftlint:disable:next function_body_length
    func todoSection(title: String, todos: [TodoItem]) -> some View {
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
                ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            if isSelectMode {
                                Button {
                                    toggleSelection(todo)
                                } label: {
                                    let isSelected = selectedTodoIDs.contains(todo.id)
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
            #if os(iOS)
            .background(Color(.systemBackground))
            #else
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    func sectionIcon(for title: String) -> some View {
        let config = sectionIconConfig(for: title)
        Image(systemName: config.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(config.color)
            .frame(width: 26, height: 26)
            .background(config.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                    .fill(TodoTagHelper.tagColor(tag).color.opacity(0.12))
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
                    .foregroundStyle(filter.color.opacity(0.25))
            }

            VStack(spacing: 6) {
                Text(emptyStateMessage)
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(.secondary)

                if selectedTag == nil && selectedFolder == nil && (selectedFilter == .inbox || selectedFilter == .all) {
                    Text("Press \(Image(systemName: "command")) N to add a new task")
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
        if let folder = selectedFolder {
            return "No todos in \"\(folder)\""
        }
        if let tag = selectedTag {
            return "No todos tagged \"\(TodoTagHelper.tagName(tag))\""
        }
        return (selectedFilter ?? .inbox).emptyMessage
    }
}
