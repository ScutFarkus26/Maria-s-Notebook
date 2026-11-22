// EditTodoForm.swift
// The to-do editor: Today's to-do section, a child's Watching list and
// meetings open it. Since the Todos screen was taken out (2026-11-22) it is
// also where a to-do is deleted.

import SwiftUI
import CoreData

// MARK: - Edit Todo Form

struct EditTodoForm: View {
    @ObservedObject var todo: CDTodoItem
    /// Closes the editor once the to-do is deleted: the host clears what it
    /// was showing.
    var onDelete: () -> Void = {}
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @State private var isConfirmingDelete = false

    var body: some View {
        // A deleted to-do has no title to bind to: the editor goes blank while
        // its host closes it, rather than reading the deleted row.
        if todo.isDeleted || todo.managedObjectContext == nil {
            Color.clear
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $todo.title)
                    .font(AppTheme.ScaledFont.titleSmall)

                TextField("Notes", text: $todo.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .font(AppTheme.ScaledFont.body)

                if let list = todo.tideListName {
                    Label(TideSyncMessages.linkedNote(listName: list), systemImage: "water.waves")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            scheduleSection

            Section {
                // Through `TodoCompletionService`, like every other tick: the
                // completion date, a repeat's next occurrence, and taking it
                // back when the switch is turned off again.
                Toggle("Completed", isOn: Binding(
                    get: { todo.isCompleted },
                    set: { isOn in
                        guard isOn != todo.isCompleted else { return }
                        if isOn {
                            TodoCompletionService.complete(todo)
                        } else {
                            TodoCompletionService.reopen(todo)
                        }
                    }
                ))

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

            Section {
                Button("Delete To-do", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        }
        .confirmationDialog("Delete this to-do?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteTodo() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: todo.title) { _, _ in saveTodoChanges() }
        .onChange(of: todo.notes) { _, _ in saveTodoChanges() }
        .onChange(of: todo.dueDate) { _, _ in saveTodoChanges() }
        .onChange(of: todo.isCompleted) { _, _ in saveTodoChanges() }
        .onChange(of: todo.recurrenceRaw) { _, _ in saveTodoChanges() }
        // The When popover and the repeat settings write straight to the todo too;
        // without these they waited for the editor to close (2026-10-10 sweep).
        .onChange(of: todo.scheduledDate) { _, _ in saveTodoChanges() }
        .onChange(of: todo.isSomeday) { _, _ in saveTodoChanges() }
        .onChange(of: todo.repeatAfterCompletion) { _, _ in saveTodoChanges() }
        .onChange(of: todo.customIntervalDays) { _, _ in saveTodoChanges() }
        .onDisappear {
            saveTodoChanges()
        }
    }

    @ViewBuilder private var scheduleSection: some View {
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

            Picker("Repeats", selection: Binding(
                get: { todo.recurrence },
                set: { todo.setRecurrence($0) }
            )) {
                ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                    Text(pattern.rawValue).tag(pattern)
                }
            }

            if todo.recurrence != .none {
                Toggle("Repeat after completion", isOn: $todo.repeatAfterCompletion)
                if todo.recurrence == .custom {
                    Stepper(
                        "Every \(customInterval) days",
                        value: Binding<Int>(
                            get: { customInterval },
                            set: { todo.customIntervalDays = Int64($0) }
                        ),
                        in: 1...365
                    )
                }
            }
        }
    }

    /// The custom interval as it repeats (`TodoRepeatRule.intervalDays`).
    private var customInterval: Int {
        todo.customIntervalDays > 0 ? Int(todo.customIntervalDays) : TodoRepeatRule.defaultCustomIntervalDays
    }

    private func formatCompletedDate(_ date: Date) -> String {
        DateFormatters.mediumDateTime.string(from: date)
    }

    private func saveTodoChanges() {
        guard !todo.isDeleted, todo.managedObjectContext != nil else { return }
        viewContext.safeSave()
    }

    /// Deletes the to-do as the Todos screen did, after asking: the host
    /// closes the editor first.
    private func deleteTodo() {
        onDelete()
        viewContext.delete(todo)
        dependencies.saveCoordinator.save(viewContext, reason: "Delete todo")
    }
}
