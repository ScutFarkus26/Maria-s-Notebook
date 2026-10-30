// ForMeToDoSection.swift
// The meeting's For Me to Do: what the guide owes the child. Her open to-dos
// can be ticked off and new lines added; nothing is written until Complete
// (`MeetingDraftModel.fileTodos`).

import CoreData
import SwiftUI

struct ForMeToDoSection: View {
    @Bindable var draft: MeetingDraftModel

    /// Every open to-do. Children are a stored list (Transformable) a fetch
    /// can't match on, so hers are picked out of the open ones (`openTodos`).
    @FetchRequest private var open: FetchedResults<CDTodoItem>

    @State private var newText = ""
    @State private var newDueDate: Date?
    @State private var isPickingDay = false
    @State private var pickedDay = Date()
    @FocusState private var isFieldFocused: Bool

    init(draft: MeetingDraftModel) {
        self.draft = draft
        _open = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: true)],
            predicate: NSPredicate(format: "isCompleted == NO")
        )
    }

    var body: some View {
        let todos = Self.openTodos(open, for: draft.studentID)
        VStack(alignment: .leading, spacing: 4) {
            if todos.isEmpty && draft.newTodos.isEmpty {
                Text("Nothing you owe her yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(todos, id: \.objectID) { todo in
                if let id = todo.id {
                    openRow(todo, id: id)
                }
            }
            ForEach(draft.newTodos) { line in
                newRow(line)
            }
            addRow
        }
    }

    /// Her open to-dos, Someday ones too: those with a due day first, soonest
    /// first, then the rest in the order they were made.
    static func openTodos(_ todos: some Sequence<CDTodoItem>, for studentID: UUID) -> [CDTodoItem] {
        let key = studentID.uuidString
        return todos
            .filter { !$0.isCompleted && $0.studentIDsArray.contains(key) }
            .sorted {
                ($0.dueDate ?? .distantFuture, $0.createdAt ?? .distantPast)
                    < ($1.dueDate ?? .distantFuture, $1.createdAt ?? .distantPast)
            }
    }

    // MARK: - Rows

    private func openRow(_ todo: CDTodoItem, id: UUID) -> some View {
        let isTicked = draft.doneTodoIDs.contains(id)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                adaptiveWithAnimation {
                    if isTicked {
                        draft.doneTodoIDs.remove(id)
                    } else {
                        draft.doneTodoIDs.insert(id)
                    }
                }
            } label: {
                Image(systemName: isTicked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isTicked ? AppColors.success : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isTicked ? "Done" : "Mark done")

            VStack(alignment: .leading, spacing: 1) {
                Text(todo.title)
                    .strikethrough(isTicked)
                    .foregroundStyle(isTicked ? .secondary : .primary)
                if let due = todo.dueDate {
                    Text("Due \(Self.label(due))")
                        .font(.caption)
                        .foregroundStyle(todo.isOverdue && !isTicked ? AppColors.destructive : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func newRow(_ line: MeetingNewTodo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "square")
                .foregroundStyle(.secondary)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(line.text)
                if let due = line.dueDate {
                    Text("Due \(Self.label(due))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Text("new")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .capsuleFill(Color.primary.opacity(UIConstants.OpacityConstants.light))

            Button {
                adaptiveWithAnimation {
                    draft.newTodos.removeAll { $0.id == line.id }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(line.text)")
        }
        .padding(.vertical, 3)
    }

    // MARK: - Adding a line

    private var addRow: some View {
        HStack(spacing: 10) {
            Button(action: add) {
                Image(systemName: "plus")
                    .foregroundStyle(.accent)
                    .font(.body.weight(.medium))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a to-do")

            TextField("Add a to-do", text: $newText)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .focused($isFieldFocused)
                .onSubmit(add)

            dueMenu
        }
        .padding(.vertical, 3)
    }

    /// The new line's due day: none unless one is picked.
    private var dueMenu: some View {
        Menu {
            Button("No Due Day") { newDueDate = nil }
            Button("Today") { newDueDate = Self.day(0) }
            Button("Tomorrow") { newDueDate = Self.day(1) }
            Button("Next Week") { newDueDate = Self.day(7) }
            Button("Pick a Day…") {
                pickedDay = newDueDate ?? Date()
                isPickingDay = true
            }
        } label: {
            Label(newDueDate.map { "Due \(Self.label($0))" } ?? "No due day", systemImage: "calendar")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(newDueDate == nil ? Color.secondary : Color.accentColor)
                .capsuleFill(Color.primary.opacity(UIConstants.OpacityConstants.light))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(newDueDate.map { "Due \(Self.label($0))" } ?? "No due day")
        .accessibilityHint("Sets when the new line is due")
        .popover(isPresented: $isPickingDay) {
            VStack(spacing: 12) {
                DatePicker("Due", selection: $pickedDay, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                Button("Set Day") {
                    newDueDate = AppCalendar.startOfDay(pickedDay)
                    isPickingDay = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private func add() {
        let text = newText.trimmed()
        guard !text.isEmpty else { return }
        draft.newTodos.append(MeetingNewTodo(text: text, dueDate: newDueDate))
        newText = ""
        newDueDate = nil
        isFieldFocused = true
    }

    private static func day(_ offset: Int) -> Date {
        AppCalendar.startOfDay(AppCalendar.addingDays(offset, to: Date()))
    }

    private static func label(_ date: Date) -> String {
        DateFormatters.shortMonthDay.string(from: date)
    }
}
