// AgendaItemRows.swift
// Agenda-specific row components (todos, calendar events) for TodayView

import SwiftUI

// MARK: - Todo Today Row

struct TodoTodayRow: View {
    let todo: TodoItem
    var onToggle: () -> Void
    var onTap: () -> Void

    private var accessibilityLabelText: String {
        var label = todo.title
        if todo.isCompleted {
            label = "Completed: \(label)"
        }
        if todo.isOverdue {
            label += ", overdue"
        }
        if let dueDate = todo.dueDate {
            label += ", due \(DateFormatters.mediumDateTime.string(from: dueDate))"
        }
        if todo.priority != .none {
            label += ", \(todo.priority.rawValue) priority"
        }
        if let progress = todo.subtasksProgressText {
            label += ", subtasks \(progress)"
        }
        return label
    }

    private var dueDateText: String? {
        guard let dueDate = todo.dueDate else { return nil }
        if Calendar.current.isDateInToday(dueDate) {
            return DateFormatters.shortTime.string(from: dueDate)
        } else if Calendar.current.isDateInYesterday(dueDate) {
            return "Yesterday"
        } else {
            return DateFormatters.shortDate.string(from: dueDate)
        }
    }

    private var checkboxView: some View {
        let borderColor: Color = todo.isCompleted ? .clear : priorityBorderColor
        let fillColor: Color = todo.isCompleted ? Color.green.opacity(0.15) : .clear

        return Circle()
            .strokeBorder(borderColor, lineWidth: 1.5)
            .background(Circle().fill(fillColor))
            .overlay {
                if todo.isCompleted {
                    Image(systemName: SFSymbol.Action.checkmark)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.success)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }

    private var priorityBorderColor: Color {
        switch todo.priority {
        case .high: return .red.opacity(0.6)
        case .medium: return .orange.opacity(0.5)
        case .low: return .blue.opacity(0.4)
        case .none: return .secondary.opacity(0.4)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                checkboxView
            }
            .buttonStyle(.plain)

            Button(action: onTap) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(todo.title)
                            .font(AppTheme.ScaledFont.callout)
                            .foregroundStyle(todo.isCompleted ? .tertiary : .primary)
                            .strikethrough(todo.isCompleted, color: Color.secondary.opacity(0.5))
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            if let dateText = dueDateText {
                                HStack(spacing: 3) {
                                    Image(systemName: SFSymbol.Time.calendar)
                                        .font(.system(size: 10))
                                    Text(dateText)
                                        .font(AppTheme.ScaledFont.caption)
                                }
                                .foregroundStyle(todo.isOverdue ? Color.red : Color.secondary)
                            }

                            if let progress = todo.subtasksProgressText {
                                HStack(spacing: 3) {
                                    Image(systemName: SFSymbol.List.checklist)
                                        .font(.system(size: 10))
                                    Text(progress)
                                        .font(AppTheme.ScaledFont.caption)
                                }
                                .foregroundStyle(todo.allSubtasksCompleted ? Color.green : Color.secondary)
                            }

                            if todo.recurrence != .none {
                                Image(systemName: SFSymbol.Action.arrowClockwise)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.purple.opacity(0.7))
                            }

                            if !todo.tags.isEmpty {
                                let firstName = TodoTagHelper.tagName(todo.tags[0])
                                let firstColor = TodoTagHelper.tagColor(todo.tags[0])
                                Text(firstName)
                                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                                    .foregroundStyle(firstColor.color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(firstColor.lightColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                if todo.tags.count > 1 {
                                    Text("+\(todo.tags.count - 1)")
                                        .font(AppTheme.ScaledFont.captionSmall)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Spacer()

                    // Priority indicator
                    if todo.priority != .none && todo.priority != .low {
                        Circle()
                            .fill(todo.priority.color)
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .buttonStyle(.subtleRow)
        }
        .sensoryFeedback(.success, trigger: todo.isCompleted)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to view details, swipe right to complete")
    }
}

// MARK: - Calendar Event List Row

struct CalendarEventListRow: View {
    let event: CalendarEvent

    private var timeString: String {
        if event.isAllDay {
            return "All day"
        } else {
            return DateFormatters.shortTime.string(from: event.startDate)
        }
    }

    private var accessibilityLabelText: String {
        var label = "Calendar event: \(event.title)"
        if event.isAllDay {
            label += ", all day"
        } else {
            label += ", at \(timeString)"
        }
        if let location = event.location, !location.isEmpty {
            label += ", at \(location)"
        }
        return label
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(timeString)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)
                    if let location = event.location, !location.isEmpty {
                        Text("\u{00B7}")
                            .foregroundStyle(.quaternary)
                        Text(location)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
    }
}
