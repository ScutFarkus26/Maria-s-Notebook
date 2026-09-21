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

    var body: some View {
        HStack(spacing: 0) {
            TodoRowComponents.priorityEdge(
                priority: todo.priority,
                trailingPadding: 9,
                gutterWidth: 12
            )

            TodoCheckboxButton(isCompleted: todo.isCompleted, action: onToggle)

            Spacer().frame(width: 12)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                TodoRowComponents.titleAndNotes(todo: todo)

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
            let tomorrow = AppCalendar.shared.date(byAdding: .day, value: 1, to: Date()) ?? Date()
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
                let tomorrow = AppCalendar.shared.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                todo.scheduledDate = AppCalendar.startOfDay(tomorrow)
                todo.isSomeday = false
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
            Button {
                let cal = AppCalendar.shared
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

            TodoRowComponents.dateChip(todo: todo)

            TodoRowComponents.recurrenceChip(todo: todo)

            TodoRowComponents.subtaskProgressChip(todo: todo, iconSize: 10)
        }
        .padding(.top, 2)
    }
}
