// TodoRowComponents.swift
// Pieces of `TodoRowCard` (the main view's to-do card), kept in their own file.
// They were shared with the old list panel's compact row until that panel
// was removed.

import SwiftUI
import CoreData

enum TodoRowComponents {
    /// The priority colour bar down the leading edge, or the blank gutter that
    /// stands in for it when the to-do has no priority. The two rows inset the
    /// bar and size the gutter differently.
    @ViewBuilder
    static func priorityEdge(
        priority: TodoPriority,
        trailingPadding: CGFloat,
        gutterWidth: CGFloat
    ) -> some View {
        if priority != .none {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(priority.color)
                .frame(width: 3)
                .padding(.vertical, 6)
                .padding(.trailing, trailingPadding)
        } else {
            Spacer()
                .frame(width: gutterWidth)
        }
    }

    /// The title plus its one-line notes preview. Returned as loose views so the
    /// enclosing `VStack`'s spacing still applies between them and whatever the
    /// row puts underneath.
    @ViewBuilder
    static func titleAndNotes(todo: CDTodoItem) -> some View {
        Text(todo.title)
            .font(AppTheme.ScaledFont.titleSmall)
            .foregroundStyle(todo.isCompleted ? .secondary : .primary)
            .strikethrough(todo.isCompleted, color: .secondary.opacity(UIConstants.OpacityConstants.half))

        if !todo.notes.isEmpty {
            Text(todo.notes)
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// The scheduled/due/someday chip, shown only when the to-do carries a date.
    @ViewBuilder
    static func dateChip(todo: CDTodoItem) -> some View {
        if todo.effectiveDate != nil || todo.isSomeday {
            TodoDateChip(todo: todo)
        }
    }

    /// The repeat badge, shown only for recurring to-dos.
    @ViewBuilder
    static func recurrenceChip(todo: CDTodoItem) -> some View {
        if todo.recurrence != .none {
            HStack(spacing: 3) {
                Image(systemName: "repeat")
                    .font(.system(size: 10))
                Text(todo.recurrence.shortLabel)
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .foregroundStyle(.purple.opacity(UIConstants.OpacityConstants.prominent))
        }
    }

    /// The "2/5" subtask badge. The card draws its icon a point larger.
    @ViewBuilder
    static func subtaskProgressChip(todo: CDTodoItem, iconSize: CGFloat) -> some View {
        if let progressText = todo.subtasksProgressText {
            HStack(spacing: 3) {
                Image(systemName: "checklist")
                    .font(.system(size: iconSize))
                Text(progressText)
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .foregroundStyle(
                todo.allSubtasksCompleted
                    ? .green.opacity(UIConstants.OpacityConstants.prominent)
                    : .secondary.opacity(UIConstants.OpacityConstants.half)
            )
        }
    }
}

// MARK: - Completion Checkbox

/// The completion circle both rows draw, including its press-in/press-out
/// spring. `action` runs inside the second animation, where each row does its
/// own thing: the list row hands the toggle back to its owner, the card mutates
/// the to-do and saves.
struct TodoCheckboxButton: View {
    let isCompleted: Bool
    let action: () -> Void

    @State private var checkboxScale: CGFloat = 1.0

    var body: some View {
        Button {
            adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                checkboxScale = 0.8
            }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                    checkboxScale = 1.0
                    action()
                }
            }
        } label: {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(isCompleted ? .secondary : .tertiary)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(checkboxScale)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .sensoryFeedback(.success, trigger: isCompleted)
        #endif
    }
}
