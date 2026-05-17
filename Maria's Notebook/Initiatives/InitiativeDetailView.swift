import SwiftUI
import CoreData

struct InitiativeDetailView: View {
    @ObservedObject var initiative: CDInitiative
    var onDelete: () -> Void

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var showEditor: Bool = false
    @State private var showNewTodoSheet: Bool = false
    @State private var inlineTodoTitle: String = ""

    private var color: Color {
        InitiativeColor.from(raw: initiative.colorRaw).swiftUIColor
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !initiative.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(initiative.notes)
                            .textSelection(.enabled)
                    }
                }

                metaRow

                Divider()

                InitiativeTodoListSection(
                    initiative: initiative,
                    inlineTitle: $inlineTodoTitle
                )
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showEditor) {
            InitiativeEditorSheet(initiative: initiative)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    toggleComplete()
                } label: {
                    Label(
                        initiative.isCompleted ? "Mark Active" : "Mark Complete",
                        systemImage: initiative.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
                    )
                }
                Button {
                    showEditor = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: initiative.symbol ?? InitiativeSymbol.defaultValue.rawValue)
                .font(.system(size: 28))
                .foregroundStyle(color)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(initiative.title.isEmpty ? "Untitled" : initiative.title)
                    .font(.title2).fontWeight(.semibold)
                    .strikethrough(initiative.isCompleted)
                if let area = initiative.area, !area.trimmed().isEmpty {
                    Text(area)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.15))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }

    private var metaRow: some View {
        HStack(spacing: 24) {
            if let deadline = initiative.deadline {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(initiative.isOverdue ? .red : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deadline").font(.caption2).foregroundStyle(.secondary)
                        Text(deadline, format: .dateTime.weekday(.abbreviated).month().day().year())
                            .font(.callout)
                            .foregroundStyle(initiative.isOverdue ? .red : .primary)
                    }
                }
            }
            if let days = initiative.daysUntilDeadline {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Time").font(.caption2).foregroundStyle(.secondary)
                        Text(timeLabel(days: days))
                            .font(.callout)
                    }
                }
            }
            if let completedAt = initiative.completedAt {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Completed").font(.caption2).foregroundStyle(.secondary)
                        Text(completedAt, format: .dateTime.month().day().year())
                            .font(.callout)
                    }
                }
            }
            Spacer()
        }
    }

    private func timeLabel(days: Int) -> String {
        if days < 0 { return "\(-days) day\(days == -1 ? "" : "s") overdue" }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "\(days) days remaining"
    }

    private func toggleComplete() {
        initiative.completedAt = initiative.isCompleted ? nil : Date()
        initiative.modifiedAt = Date()
        _ = saveCoordinator.save(modelContext, reason: "Toggle Initiative Complete")
        if initiative.isCompleted {
            TodoNotificationService.shared.cancelNotifications(for: initiative, context: modelContext)
        } else {
            Task { @MainActor in
                try? await TodoNotificationService.shared.rescheduleNotifications(for: initiative, context: modelContext)
            }
        }
    }
}

// MARK: - Embedded todo list section

struct InitiativeTodoListSection: View {
    @ObservedObject var initiative: CDInitiative
    @Binding var inlineTitle: String
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @FetchRequest private var todos: FetchedResults<CDTodoItemEntity>

    init(initiative: CDInitiative, inlineTitle: Binding<String>) {
        self.initiative = initiative
        self._inlineTitle = inlineTitle
        let idString = initiative.id?.uuidString ?? ""
        _todos = FetchRequest<CDTodoItemEntity>(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \CDTodoItemEntity.isCompleted, ascending: true),
                NSSortDescriptor(keyPath: \CDTodoItemEntity.dueDate, ascending: true),
                NSSortDescriptor(keyPath: \CDTodoItemEntity.orderIndex, ascending: true)
            ],
            predicate: NSPredicate(format: "initiativeID == %@", idString)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Todos")
                    .font(.headline)
                Text("\(todos.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                TextField("Add a todo and press Return", text: $inlineTitle)
                    .textFieldStyle(.plain)
                    .onSubmit { addTodo() }
                if !inlineTitle.trimmed().isEmpty {
                    Button("Add") { addTodo() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if todos.isEmpty {
                Text("No todos yet — add a few steps above to plan this initiative.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(todos, id: \.objectID) { todo in
                    todoRow(todo)
                }
            }
        }
    }

    @ViewBuilder
    private func todoRow(_ todo: CDTodoItemEntity) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                toggleTodo(todo)
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title.isEmpty ? "Untitled" : todo.title)
                    .strikethrough(todo.isCompleted)
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                if let due = todo.dueDate {
                    Text("Due \(due, format: .dateTime.month().day())")
                        .font(.caption2)
                        .foregroundStyle(due < Calendar.current.startOfDay(for: Date()) && !todo.isCompleted ? .red : .secondary)
                }
            }
            Spacer()
            Button {
                unlinkTodo(todo)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from this initiative")
        }
        .padding(.vertical, 4)
    }

    private func addTodo() {
        let trimmed = inlineTitle.trimmed()
        guard !trimmed.isEmpty else { return }
        let todo = CDTodoItemEntity(context: modelContext)
        todo.title = trimmed
        todo.initiativeID = initiative.id?.uuidString
        inlineTitle = ""
        saveCoordinator.save(modelContext, reason: "Add Todo to Initiative")
    }

    private func toggleTodo(_ todo: CDTodoItemEntity) {
        todo.isCompleted.toggle()
        todo.completedAt = todo.isCompleted ? Date() : nil
        saveCoordinator.save(modelContext, reason: "Toggle Todo Complete")
    }

    private func unlinkTodo(_ todo: CDTodoItemEntity) {
        todo.initiativeID = nil
        saveCoordinator.save(modelContext, reason: "Unlink Todo from Initiative")
    }
}
