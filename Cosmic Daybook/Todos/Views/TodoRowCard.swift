// TodoRowCard.swift
// Elegant todo row card inspired by Things and Bear

import SwiftUI
import CoreData

struct TodoRowCard: View {
    @ObservedObject var todo: CDTodoItem
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// Persists a reschedule/date change via `SaveCoordinator` (which surfaces a
    /// "Couldn't Save" alert on failure). Extracted from `body` so the swipe and
    /// "Move to…" menu actions don't inflate the view body's type-check time.
    private func persist() {
        saveCoordinator.save(viewContext, reason: "Reschedule to-do")
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            rowLabel
        }
        .buttonStyle(.plain)
        .opacity(todo.isCompleted ? 0.5 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) { trailingSwipeActions }
        .swipeActions(edge: .leading) { leadingSwipeActions }
        .contextMenu { rowContextMenu }
        .accessibilityAction(named: Text(todo.isCompleted ? "Mark Incomplete" : "Mark Complete")) {
            toggleCompletion()
        }
        .accessibilityAction(named: Text("Edit")) {
            onEdit()
        }
        .accessibilityAction(named: Text("Delete")) {
            onDelete()
        }
    }

    @ViewBuilder
    private var rowLabel: some View {
        HStack(spacing: 0) {
            TodoRowComponents.priorityEdge(
                priority: todo.priority,
                trailingPadding: 11,
                gutterWidth: 14
            )

            TodoCheckboxButton(isCompleted: todo.isCompleted, action: { toggleCompletion() })

            Spacer().frame(width: 14)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                TodoRowComponents.titleAndNotes(todo: todo)

                if todo.effectiveDate != nil || todo.isSomeday ||
                    !todo.tagsArray.isEmpty || todo.recurrence != .none {
                    HStack(spacing: 6) {
                        TodoRowComponents.dateChip(todo: todo)

                        TodoRowComponents.recurrenceChip(todo: todo)

                        if !todo.tagsArray.isEmpty {
                            tagBadgeStack
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            // Subtask count
            TodoRowComponents.subtaskProgressChip(todo: todo, iconSize: 11)
        }
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// Flips the to-do and stamps its completion date. Runs inside
    /// `TodoCheckboxButton`'s animation, and backs the accessibility action.
    private func toggleCompletion() {
        todo.isCompleted.toggle()
        todo.completedAt = todo.isCompleted ? Date() : nil
        viewContext.safeSave()
    }

    @ViewBuilder
    private var trailingSwipeActions: some View {
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }

        Button {
            onEdit()
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.blue)
    }

    @ViewBuilder
    private var leadingSwipeActions: some View {
        Button {
            todo.scheduledDate = AppCalendar.startOfDay(Date())
            todo.isSomeday = false
            persist()
        } label: {
            Label("Today", systemImage: "star.fill")
        }
        .tint(.orange)

        Button {
            todo.scheduledDate = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))
            todo.isSomeday = false
            persist()
        } label: {
            Label("Tomorrow", systemImage: "sunrise")
        }
        .tint(.orange.opacity(UIConstants.OpacityConstants.heavy))

        Button {
            todo.scheduledDate = nextMonday()
            todo.isSomeday = false
            persist()
        } label: {
            Label("+1 Week", systemImage: "calendar.badge.plus")
        }
        .tint(.purple)
    }

    @ViewBuilder
    private var rowContextMenu: some View {
        Button {
            onEdit()
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button {
            togglePriority()
        } label: {
            Label("Change Priority", systemImage: "flag")
        }

        Divider()

        Menu("Move to...") {
            Button {
                todo.scheduledDate = AppCalendar.startOfDay(Date())
                todo.isSomeday = false
                persist()
            } label: {
                Label("Today", systemImage: "star.fill")
            }
            Button {
                todo.scheduledDate = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))
                todo.isSomeday = false
                persist()
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
            Button {
                todo.scheduledDate = nextMonday()
                todo.isSomeday = false
                persist()
            } label: {
                Label("Next Week", systemImage: "calendar.badge.plus")
            }
            Button {
                todo.scheduledDate = nil
                todo.isSomeday = true
                persist()
            } label: {
                Label("Someday", systemImage: "moon.zzz")
            }
            Divider()
            Button {
                todo.scheduledDate = nil
                todo.dueDate = nil
                todo.isSomeday = false
                persist()
            } label: {
                Label("Remove Date", systemImage: "xmark.circle")
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func togglePriority() {
        switch todo.priority {
        case .none: todo.priority = .low
        case .low: todo.priority = .medium
        case .medium: todo.priority = .high
        case .high: todo.priority = .none
        }
        viewContext.safeSave()
    }

    private func nextMonday() -> Date {
        let today = AppCalendar.startOfDay(Date())
        let cal = AppCalendar.shared
        var d = cal.date(byAdding: .day, value: 1, to: today) ?? today
        while cal.component(.weekday, from: d) != 2 {
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }

    @ViewBuilder
    private var tagBadgeStack: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: todo.tagsArray.count, through: 1, by: -1)), id: \.self) { visibleCount in
                tagBadgeRow(tags: todo.tagsArray, visibleCount: visibleCount)
            }

            Text("+\(todo.tagsArray.count)")
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(.tertiary)
        }
    }

    private func tagBadgeRow(tags: [String], visibleCount: Int) -> some View {
        let visibleTags = Array(tags.prefix(visibleCount))
        let hiddenCount = max(tags.count - visibleCount, 0)

        return HStack(spacing: 6) {
            ForEach(Array(visibleTags.enumerated()), id: \.offset) { _, tag in
                TagBadge(tag: tag, compact: true)
            }

            if hiddenCount > 0 {
                Text("+\(hiddenCount)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
