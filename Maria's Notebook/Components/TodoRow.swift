import SwiftUI
import SwiftData

struct TodoRow: View {
    let todo: TodoItem
    let students: [Student]
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    private var assignedStudents: [Student] {
        students.filter { todo.studentIDs.contains($0.id.uuidString) }
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
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

    private func formatReminderBadge(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func formatTodoAsText(_ todo: TodoItem) -> String {
        var text = "\u{1F4CB} \(todo.title)\n"

        // Priority
        if todo.priority != .none {
            let priorityEmoji = todo.priority == .high
                ? "\u{1F534}" : todo.priority == .medium ? "\u{1F7E0}" : "\u{1F535}"
            text += "\(priorityEmoji) Priority: \(todo.priority.rawValue)\n"
        }

        // Due date
        if let dueDate = todo.dueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            text += "\u{1F4C5} Due: \(formatter.string(from: dueDate))\n"
        }

        // Assigned students
        if !assignedStudents.isEmpty {
            let names = assignedStudents.map { $0.firstName }.joined(separator: ", ")
            text += "\u{1F465} Assigned to: \(names)\n"
        }

        // Reminder
        if let reminderDate = todo.reminderDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            text += "\u{1F514} Reminder: \(formatter.string(from: reminderDate))\n"
        }

        // Time estimate
        if let estimated = todo.estimatedMinutes, estimated > 0 {
            text += "\u{23F1}\u{FE0F} Estimated time: \(formatTimeEstimate(estimated))\n"
        }

        // Mood
        if let mood = todo.mood {
            text += "\(mood.emoji) Mood: \(mood.rawValue)\n"
        }

        // Reflection
        if !todo.reflectionNotes.isEmpty {
            text += "\u{1F4AD} Reflection: \(todo.reflectionNotes)\n"
        }

        // Subtasks
        let shareSubs = todo.subtasks ?? []
        if !shareSubs.isEmpty {
            text += "\n\u{2705} Subtasks (\(shareSubs.filter { $0.isCompleted }.count)/\(shareSubs.count)):\n"
            for subtask in shareSubs.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let checkbox = subtask.isCompleted ? "\u{2611}\u{FE0F}" : "\u{2610}"
                text += "  \(checkbox) \(subtask.title)\n"
            }
        }

        // Notes
        if !todo.notes.isEmpty {
            text += "\n\u{1F4DD} Notes:\n\(todo.notes)\n"
        }

        return text
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

            // Checkbox
            Button {
                adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    checkboxScale = 0.8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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

            Spacer().frame(width: 12)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .strikethrough(todo.isCompleted, color: .secondary.opacity(0.5))

                if !todo.notes.isEmpty {
                    Text(todo.notes)
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if !assignedStudents.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text(assignedStudents.map { $0.firstName }.joined(separator: ", "))
                                .font(AppTheme.ScaledFont.captionSemibold)
                        }
                        .foregroundStyle(.blue.opacity(0.7))
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
                        .foregroundStyle(.purple.opacity(0.7))
                    }

                    if let progressText = todo.subtasksProgressText {
                        HStack(spacing: 3) {
                            Image(systemName: "checklist")
                                .font(.system(size: 10))
                            Text(progressText)
                                .font(AppTheme.ScaledFont.captionSemibold)
                        }
                        .foregroundStyle(todo.allSubtasksCompleted ? .green.opacity(0.7) : .secondary.opacity(0.5))
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 8)
        }
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .opacity(todo.isCompleted ? 0.5 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
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
            .tint(.orange.opacity(0.8))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .contextMenu {
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
    }
}
