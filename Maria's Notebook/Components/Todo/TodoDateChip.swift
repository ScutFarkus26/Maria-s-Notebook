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
        HStack(spacing: 3) {
            if let icon = chipIcon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
            }
            Text(chipText)
                .font(AppTheme.ScaledFont.captionSemibold)

            // Deadline flag indicator
            if todo.hasDeadline && !todo.isOverdue {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.6))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(chipForeground)
        .background(chipBackground, in: Capsule(style: .continuous))
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
            return DateFormatters.weekdayAbbrev.string(from: date)
        case .future(let date):
            return DateFormatters.shortMonthDay.string(from: date)
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
        case .overdue: return .red
        case .today: return .orange
        case .tomorrow: return .orange.opacity(UIConstants.OpacityConstants.heavy)
        case .thisWeek: return .secondary
        case .future: return .secondary.opacity(0.6)
        case .someday: return .secondary.opacity(0.6)
        case .noDate: return .secondary.opacity(UIConstants.OpacityConstants.half)
        }
    }

    private var chipBackground: some ShapeStyle {
        switch chipState {
        case .overdue: return AnyShapeStyle(Color.red.opacity(UIConstants.OpacityConstants.light))
        case .today: return AnyShapeStyle(Color.orange.opacity(UIConstants.OpacityConstants.light))
        case .tomorrow: return AnyShapeStyle(Color.orange.opacity(UIConstants.OpacityConstants.veryFaint))
        case .thisWeek: return AnyShapeStyle(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        case .future: return AnyShapeStyle(Color.clear)
        case .someday: return AnyShapeStyle(Color.clear)
        case .noDate: return AnyShapeStyle(Color.clear)
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
        return DateFormatters.shortMonthDay.string(from: date)
    }
}
