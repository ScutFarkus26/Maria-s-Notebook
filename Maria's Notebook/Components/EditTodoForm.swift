// EditTodoForm.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import SwiftData

// MARK: - Edit Todo Form

struct EditTodoForm: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $todo.title)
                    .font(AppTheme.ScaledFont.titleSmall)

                TextField("Notes", text: $todo.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .font(AppTheme.ScaledFont.body)
            }

            Section("Schedule") {
                HStack {
                    Text("When")
                    Spacer()
                    TodoSchedulePickerButton(
                        scheduledDate: $todo.scheduledDate,
                        dueDate: $todo.dueDate,
                        isSomeday: $todo.isSomeday
                    )
                }

                Picker("Repeats", selection: $todo.recurrence) {
                    ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                        Text(pattern.rawValue).tag(pattern)
                    }
                }

                if todo.recurrence != .none {
                    Toggle("Repeat after completion", isOn: $todo.repeatAfterCompletion)
                    if todo.recurrence == .custom {
                        Stepper(
                            "Every \(todo.customIntervalDays ?? 7) days",
                            value: Binding(
                                get: { todo.customIntervalDays ?? 7 },
                                set: { todo.customIntervalDays = $0 }
                            ),
                            in: 1...365
                        )
                    }
                }
            }

            Section("Organization") {
                Picker("Priority", selection: $todo.priority) {
                    ForEach(TodoPriority.allCases, id: \.self) { p in
                        HStack {
                            Circle().fill(priorityColorForPicker(p)).frame(width: 8, height: 8)
                            Text(p.rawValue)
                        }
                        .tag(p)
                    }
                }

            }

            Section("Tags") {
                TagPicker(selectedTags: $todo.tags)
            }

            Section {
                Toggle("Completed", isOn: $todo.isCompleted)

                if todo.isCompleted, let completedAt = todo.completedAt {
                    HStack {
                        Text("Completed")
                        Spacer()
                        Text(formatCompletedDate(completedAt))
                            .foregroundStyle(.secondary)
                    }
                    .font(AppTheme.ScaledFont.body)
                }
            }
        }
        .onChange(of: todo.title) { _, _ in saveTodoChanges() }
        .onChange(of: todo.notes) { _, _ in saveTodoChanges() }
        .onChange(of: todo.dueDate) { _, _ in saveTodoChanges() }
        .onChange(of: todo.priority) { _, _ in saveTodoChanges() }
        .onChange(of: todo.tags) { _, _ in saveTodoChanges() }
        .onChange(of: todo.isCompleted) { _, _ in saveTodoChanges() }
        .onDisappear {
            saveTodoChanges()
        }
    }

    private func priorityColorForPicker(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func formatCompletedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func saveTodoChanges() {
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to save todo changes: \(error)")
        }
    }
}
