// GoingOutChecklistSection.swift
// Interactive checklist section within the Going-Out detail view.

import SwiftUI
import SwiftData

struct GoingOutChecklistSection: View {
    @Bindable var goingOut: GoingOut
    @Environment(\.modelContext) private var modelContext
    @State private var newItemTitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Planning Checklist")
                .font(.subheadline)
                .fontWeight(.semibold)

            // Existing items
            ForEach(goingOut.sortedChecklistItems) { item in
                checklistRow(item)
            }

            // Add new item
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                TextField("Add checklist item…", text: $newItemTitle)
                    .font(.subheadline)
                    .onSubmit {
                        addItem()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func checklistRow(_ item: GoingOutChecklistItem) -> some View {
        HStack(spacing: 8) {
            Button {
                item.isCompleted.toggle()
                modelContext.safeSave()
            } label: {
                Image(systemName: item.isCompleted ? SFSymbol.Action.checkmarkCircleFill : "circle")
                    .font(.body)
                    .foregroundStyle(item.isCompleted ? AppColors.success : Color.gray)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.subheadline)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .strikethrough(item.isCompleted)

            Spacer()

            Button {
                deleteItem(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
    }

    private func addItem() {
        let trimmed = newItemTitle.trimmed()
        guard !trimmed.isEmpty else { return }

        let nextOrder = (goingOut.checklistItems?.count ?? 0)
        let item = GoingOutChecklistItem(
            goingOutID: goingOut.id,
            title: trimmed,
            sortOrder: nextOrder
        )
        item.goingOut = goingOut
        modelContext.insert(item)
        modelContext.safeSave()
        newItemTitle = ""
    }

    private func deleteItem(_ item: GoingOutChecklistItem) {
        modelContext.delete(item)
        modelContext.safeSave()
    }
}
