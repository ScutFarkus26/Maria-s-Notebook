// TodoChecklistSection.swift
// The to-do editor's checklist: tick, rename, delete and add items.

import Combine
import SwiftUI
import CoreData

/// The editor's checklist. New Todo can give a to-do a checklist, but since
/// the old edit sheet went (934e90c7) nothing could tick, rename or remove
/// its items, so the row's "0/3" never moved (bug hunt 2026-11-03, #49).
/// Every change is written to the to-do and saved at once, as the editor's
/// other fields are.
struct TodoChecklistSection: View {
    @ObservedObject var todo: CDTodoItem
    @Environment(\.managedObjectContext) private var viewContext
    @State private var newItemTitle = ""
    @FocusState private var isAddFieldFocused: Bool

    private var items: [CDTodoSubtask] {
        ((todo.subtasks as? Set<CDTodoSubtask>) ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        Section {
            ForEach(items, id: \.objectID) { item in
                TodoChecklistRow(
                    subtask: item,
                    onToggle: { toggle(item) },
                    onRename: { rename(item, to: $0) },
                    onDelete: { delete(item) }
                )
            }

            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Add an item", text: $newItemTitle)
                    .textFieldStyle(.plain)
                    .focused($isAddFieldFocused)
                    .onSubmit(addItem)
            }
        } header: {
            HStack {
                Text("Checklist")
                Spacer()
                if let progress = todo.subtasksProgressText {
                    Text(progress)
                }
            }
        }
    }

    private func addItem() {
        let title = newItemTitle.trimmed()
        guard !title.isEmpty else { return }
        let item = CDTodoSubtask(context: viewContext)
        item.title = title
        item.orderIndex = (items.last?.orderIndex ?? -1) + 1
        todo.addToSubtasks(item)
        newItemTitle = ""
        isAddFieldFocused = true
        save()
    }

    private func toggle(_ item: CDTodoSubtask) {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        save()
    }

    private func rename(_ item: CDTodoSubtask, to title: String) {
        item.title = title
        save()
    }

    private func delete(_ item: CDTodoSubtask) {
        todo.removeFromSubtasks(item)
        viewContext.delete(item)
        save()
    }

    /// Saves, and tells the to-do's row its checklist changed: a tick
    /// changes only the item, which the row doesn't watch.
    private func save() {
        todo.objectWillChange.send()
        viewContext.safeSave()
    }
}

/// One checklist item: its tick, its name (edited in place) and a delete
/// button.
private struct TodoChecklistRow: View {
    @ObservedObject var subtask: CDTodoSubtask
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var title: String
    @FocusState private var isFocused: Bool

    init(
        subtask: CDTodoSubtask,
        onToggle: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.subtask = subtask
        self.onToggle = onToggle
        self.onRename = onRename
        self.onDelete = onDelete
        _title = State(initialValue: subtask.title)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(subtask.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isCompleted ? "Done" : "Not done")
            .accessibilityHint("Ticks or unticks this item")

            TextField("Item", text: $title)
                .textFieldStyle(.plain)
                .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                .strikethrough(subtask.isCompleted)
                .focused($isFocused)
                .onSubmit(commitTitle)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitTitle() }
                }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(subtask.title)")
        }
    }

    /// Writes the edited name; an emptied one goes back to what it was.
    private func commitTitle() {
        let trimmed = title.trimmed()
        if trimmed.isEmpty {
            title = subtask.title
        } else if trimmed != subtask.title {
            onRename(trimmed)
        }
    }
}
