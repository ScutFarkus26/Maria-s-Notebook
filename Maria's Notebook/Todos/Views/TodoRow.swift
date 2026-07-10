import SwiftUI
import CoreData

struct TodoRow: View {
    let todo: CDTodoItem
    let students: [CDStudent]
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    private var assignedStudents: [CDStudent] {
        students.filter { todo.studentIDsArray.contains($0.id?.uuidString ?? "") }
    }

    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func formatTimeEstimate(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    @State private var checkboxScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 0) {
            // Priority left-edge bar
            if todo.priority != .none {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(priorityColor(todo.priority))
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .padding(.trailing, 9)
            } else {
                Spacer().frame(width: 12)
            }

            checkboxButton

            Spacer().frame(width: 12)

            // Content
            VStack(alignment: .leading, spacing: 3) {
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

                badgeRow
            }

            Spacer(minLength: 8)
        }
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .opacity(todo.isCompleted ? 0.5 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) { trailingSwipeActions }
        .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingSwipeActions }
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .accessibilityAction(named: Text(todo.isCompleted ? "Mark Incomplete" : "Mark Complete")) {
            onToggle()
        }
        .accessibilityAction(named: Text("Edit")) {
            onEdit()
        }
        .accessibilityAction(named: Text("Delete")) {
            onDelete()
        }
        .contextMenu { rowContextMenu }
    }

    private var checkboxButton: some View {
        Button {
            adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                checkboxScale = 0.8
            }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                    checkboxScale = 1.0
                    onToggle()
                }
            }
        } label: {
            Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(todo.isCompleted ? .secondary : .tertiary)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(checkboxScale)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .sensoryFeedback(.success, trigger: todo.isCompleted)
        #endif
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
            onToggle()
        } label: {
            Label(todo.isCompleted ? "Incomplete" : "Complete",
                  systemImage: todo.isCompleted ? "arrow.uturn.backward" : "checkmark")
        }
        .tint(todo.isCompleted ? .orange : .green)

        Button {
            todo.scheduledDate = AppCalendar.startOfDay(Date())
            todo.isSomeday = false
        } label: {
            Label("Today", systemImage: "star.fill")
        }
        .tint(.orange)

        Button {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            todo.scheduledDate = AppCalendar.startOfDay(tomorrow)
            todo.isSomeday = false
        } label: {
            Label("Tomorrow", systemImage: "sunrise")
        }
        .tint(.orange.opacity(UIConstants.OpacityConstants.heavy))
    }

    @ViewBuilder
    private var rowContextMenu: some View {
        Button { onEdit() } label: {
            Label("Edit", systemImage: "pencil")
        }
        Divider()
        Menu("Move to...") {
            Button {
                todo.scheduledDate = AppCalendar.startOfDay(Date())
                todo.isSomeday = false
            } label: {
                Label("Today", systemImage: "star.fill")
            }
            Button {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                todo.scheduledDate = AppCalendar.startOfDay(tomorrow)
                todo.isSomeday = false
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
            Button {
                let cal = Calendar.current
                let weekday = cal.component(.weekday, from: Date())
                let daysUntilMonday = weekday == 1 ? 1 : (9 - weekday)
                let nextMon = cal.date(byAdding: .day, value: daysUntilMonday, to: Date()) ?? Date()
                todo.scheduledDate = AppCalendar.startOfDay(nextMon)
                todo.isSomeday = false
            } label: {
                Label("Next Week", systemImage: "calendar.badge.plus")
            }
            Divider()
            Button {
                todo.isSomeday = true
                todo.scheduledDate = nil
            } label: {
                Label("Someday", systemImage: "moon.zzz")
            }
            Button {
                todo.scheduledDate = nil
                todo.dueDate = nil
                todo.isSomeday = false
            } label: {
                Label("Remove Date", systemImage: "calendar.badge.minus")
            }
        }
        Divider()
        Button(role: .destructive) { onDelete() } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var badgeRow: some View {
        HStack(spacing: 6) {
            if !assignedStudents.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                    Text(assignedStudents.map(\.firstName).joined(separator: ", "))
                        .font(AppTheme.ScaledFont.captionSemibold)
                }
                .foregroundStyle(.blue.opacity(UIConstants.OpacityConstants.prominent))
            }

            if todo.effectiveDate != nil || todo.isSomeday {
                TodoDateChip(todo: todo)
            }

            if todo.recurrence != .none {
                HStack(spacing: 3) {
                    Image(systemName: "repeat")
                        .font(.system(size: 10))
                    Text(todo.recurrence.shortLabel)
                        .font(AppTheme.ScaledFont.captionSemibold)
                }
                .foregroundStyle(.purple.opacity(UIConstants.OpacityConstants.prominent))
            }

            if let progressText = todo.subtasksProgressText {
                HStack(spacing: 3) {
                    Image(systemName: "checklist")
                        .font(.system(size: 10))
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
        .padding(.top, 2)
    }
}
