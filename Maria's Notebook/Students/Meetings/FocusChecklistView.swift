import SwiftUI
import CoreData

/// A pending focus item that hasn't been persisted yet (created during this meeting session).
struct PendingFocusItem: Identifiable {
    let id = UUID()
    var text: String
}

/// Structured focus checklist that replaces the free-text focus field.
/// Shows active carry-forward items with resolve/drop controls and allows adding new items.
struct FocusChecklistView: View {
    let existingItems: [CDStudentFocusItem]
    @Binding var pendingNewItems: [PendingFocusItem]
    @Binding var resolvedItemIDs: Set<UUID>
    @Binding var droppedItemIDs: Set<UUID>

    @State private var newItemText: String = ""
    @FocusState private var isNewItemFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus Items")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                // Carry-forward items from previous meetings
                ForEach(existingItems) { item in
                    if let itemID = item.id {
                        existingItemRow(item, itemID: itemID)
                    }
                }

                // New items added in this session
                ForEach($pendingNewItems) { $item in
                    pendingItemRow($item)
                }

                // Add new item row
                addItemRow
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
            )
        }
    }

    // MARK: - Existing Item Row

    private func existingItemRow(_ item: CDStudentFocusItem, itemID: UUID) -> some View {
        let isResolved = resolvedItemIDs.contains(itemID)
        let isDropped = droppedItemIDs.contains(itemID)

        return HStack(spacing: 8) {
            // Checkbox
            Button {
                adaptiveWithAnimation {
                    if isResolved {
                        resolvedItemIDs.remove(itemID)
                    } else {
                        droppedItemIDs.remove(itemID)
                        resolvedItemIDs.insert(itemID)
                    }
                }
            } label: {
                Image(systemName: isResolved ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isResolved ? AppColors.success : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)

            // Text
            Text(item.text)
                .font(.body)
                .strikethrough(isResolved || isDropped)
                .foregroundStyle(isResolved || isDropped ? .secondary : .primary)

            Spacer()

            // Carried weeks badge
            if let createdAt = item.createdAt {
                let weeks = weeksCarried(since: createdAt)
                if weeks > 0 {
                    Text("\(weeks)w")
                        .font(.caption2)
                        .foregroundStyle(weeks >= 4 ? AppColors.warning : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(UIConstants.OpacityConstants.light))
                        )
                }
            }

            // Drop button
            if !isResolved {
                Button {
                    adaptiveWithAnimation {
                        if isDropped {
                            droppedItemIDs.remove(itemID)
                        } else {
                            resolvedItemIDs.remove(itemID)
                            droppedItemIDs.insert(itemID)
                        }
                    }
                } label: {
                    Image(systemName: isDropped ? "arrow.uturn.backward" : "xmark")
                        .font(.caption)
                        .foregroundStyle(isDropped ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Pending Item Row

    private func pendingItemRow(_ item: Binding<PendingFocusItem>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.body)

            TextField("Focus item...", text: item.text)
                .font(.body)
                .textFieldStyle(.plain)

            Spacer()

            Button {
                adaptiveWithAnimation {
                    pendingNewItems.removeAll { $0.id == item.wrappedValue.id }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Add Item Row

    private var addItemRow: some View {
        HStack(spacing: 8) {
            Button {
                addNewItem(refocus: true)
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.accent)
                    .font(.body)
            }
            .buttonStyle(.plain)

            TextField("Add focus item...", text: $newItemText)
                .font(.body)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .focused($isNewItemFocused)
                .onSubmit {
                    addNewItem(refocus: true)
                }
                .onChange(of: isNewItemFocused) { _, isFocused in
                    if !isFocused {
                        addNewItem(refocus: false)
                    }
                }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func addNewItem(refocus: Bool) {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingNewItems.append(PendingFocusItem(text: trimmed))
        newItemText = ""
        if refocus {
            isNewItemFocused = true
        }
    }

    private func weeksCarried(since date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekOfYear], from: date, to: Date())
        return max(0, components.weekOfYear ?? 0)
    }
}
