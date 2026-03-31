// GoingOutChecklistSection.swift
// Interactive checklist section within the Going-Out detail view.

import SwiftUI
import CoreData

struct GoingOutChecklistSection: View {
    @ObservedObject var goingOut: GoingOut
    @Environment(\.managedObjectContext) private var modelContext
    @State private var newItemTitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Planning Checklist")
                .font(.subheadline)
                .fontWeight(.semibold)

            // Existing items
            ForEach(goingOut.sortedChecklistItems, id: \.objectID) { item in
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
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.ghost))
        )
    }

    private func addItem() {
        let trimmed = newItemTitle.trimmed()
        guard !trimmed.isEmpty else { return }

        let nextOrder = goingOut.sortedChecklistItems.count
        let item = CDGoingOutChecklistItem(context: modelContext)
        item.goingOutID = (goingOut.id ?? UUID()).uuidString
        item.title = trimmed
        item.sortOrder = Int64(nextOrder)
        item.goingOut = goingOut
        modelContext.safeSave()
        newItemTitle = ""
    }

    private func deleteItem(_ item: GoingOutChecklistItem) {
        modelContext.delete(item)
        modelContext.safeSave()
    }
}
