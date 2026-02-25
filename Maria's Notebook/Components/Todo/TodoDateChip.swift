import SwiftUI

/// A tappable capsule chip that displays a todo's scheduling state and opens the When popover.
struct TodoDateChip: View {
    @Bindable var todo: TodoItem
    @State private var showWhenPopover = false

    var body: some View {
        Button {
            showWhenPopover = true
        } label: {
            chipContent
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showWhenPopover, arrowEdge: .bottom) {
            TodoWhenPopover(
                scheduledDate: $todo.scheduledDate,
                dueDate: $todo.dueDate,
                isSomeday: $todo.isSomeday,
                onDismiss: { showWhenPopover = false }
            )
        }
    }

    @ViewBuilder
    private var chipContent: some View {
        HStack(spacing: 4) {
            if let icon = chipIcon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
            }
            Text(chipText)
                .font(.system(size: 12, weight: .medium, design: .rounded))

            // Deadline flag indicator
            if todo.hasDeadline && !todo.isOverdue {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.verySmall)
        .padding(.vertical, AppTheme.Spacing.xxsmall)
        .foregroundStyle(chipForeground)
        .background(chipBackground, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chipBorderColor, lineWidth: UIConstants.StrokeWidth.thin)
        )
    }

    // MARK: - Chip State

    private var chipState: ChipState {
        if todo.isOverdue {
            return .overdue
        }
        if todo.isSomeday {
            return .someday
        }
        if let effective = todo.scheduledDate ?? todo.dueDate {
            let cal = Calendar.current
            if cal.isDateInToday(effective) {
                return .today
            }
            if cal.isDateInTomorrow(effective) {
                return .tomorrow
            }
            if isThisWeek(effective) {
                return .thisWeek(effective)
            }
            return .future(effective)
        }
        return .noDate
    }

    private enum ChipState {
        case overdue
        case today
        case tomorrow
        case thisWeek(Date)
        case future(Date)
        case someday
        case noDate
    }

    // MARK: - Visual Properties

    private var chipText: String {
        switch chipState {
        case .overdue:
            if let due = todo.dueDate {
                return TodoDateChip.formatRelative(due)
            }
            return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        case .future(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        case .someday: return "Someday"
        case .noDate: return "When"
        }
    }

    private var chipIcon: String? {
        switch chipState {
        case .overdue: return "exclamationmark.circle"
        case .today: return "star.fill"
        case .someday: return "moon.zzz"
        case .noDate: return "calendar.badge.plus"
        default: return nil
        }
    }

    private var chipForeground: Color {
        switch chipState {
        case .overdue: return .white
        case .today: return .blue
        case .tomorrow: return .orange
        case .thisWeek: return .primary
        case .future: return .secondary
        case .someday: return .secondary
        case .noDate: return .gray
        }
    }

    private var chipBackground: some ShapeStyle {
        switch chipState {
        case .overdue: return AnyShapeStyle(Color.red)
        case .today: return AnyShapeStyle(Color.blue.opacity(UIConstants.OpacityConstants.medium))
        case .tomorrow: return AnyShapeStyle(Color.orange.opacity(UIConstants.OpacityConstants.faint))
        case .thisWeek: return AnyShapeStyle(Color.primary.opacity(UIConstants.OpacityConstants.faint))
        case .future: return AnyShapeStyle(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        case .someday: return AnyShapeStyle(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        case .noDate: return AnyShapeStyle(Color.clear)
        }
    }

    private var chipBorderColor: Color {
        switch chipState {
        case .overdue: return .clear
        case .today: return .blue.opacity(UIConstants.OpacityConstants.statusBg)
        case .tomorrow: return .orange.opacity(UIConstants.OpacityConstants.accent)
        case .thisWeek, .future: return .primary.opacity(UIConstants.OpacityConstants.faint)
        case .someday: return .primary.opacity(UIConstants.OpacityConstants.faint)
        case .noDate: return .primary.opacity(UIConstants.OpacityConstants.subtle)
        }
    }

    // MARK: - Helpers

    private func isThisWeek(_ date: Date) -> Bool {
        let cal = Calendar.current
        return cal.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }

    private static func formatRelative(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
