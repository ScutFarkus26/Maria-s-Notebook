import SwiftUI
import CoreData

/// Last week's focus items, ticked off or dropped, and new ones for next week.
/// The meeting opens here because it starts by looking back at what the
/// child set out to do.
struct FocusChecklistView: View {
    @Bindable var draft: MeetingDraftModel

    @State private var newItemText: String = ""
    @FocusState private var isNewItemFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last Week's Focus")
                .font(.headline)
                .padding(.bottom, 4)

            if draft.activeFocusItems.isEmpty && draft.pendingFocus.isEmpty {
                Text("Nothing carried over.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(draft.activeFocusItems) { item in
                if let itemID = item.id {
                    existingItemRow(item, itemID: itemID)
                }
            }

            ForEach(draft.pendingFocus) { item in
                pendingItemRow(itemID: item.id)
            }

            addItemRow
        }
    }

    // MARK: - Existing Item Row

    private func existingItemRow(_ item: CDStudentFocusItem, itemID: UUID) -> some View {
        let isResolved = draft.resolvedFocusIDs.contains(itemID)
        let isDropped = draft.droppedFocusIDs.contains(itemID)

        return HStack(spacing: 10) {
            Button {
                adaptiveWithAnimation {
                    if isResolved {
                        draft.resolvedFocusIDs.remove(itemID)
                    } else {
                        draft.droppedFocusIDs.remove(itemID)
                        draft.resolvedFocusIDs.insert(itemID)
                    }
                }
            } label: {
                Image(systemName: isResolved ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isResolved ? AppColors.success : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isResolved ? "Done" : "Mark done")

            Text(item.text)
                .strikethrough(isResolved || isDropped)
                .foregroundStyle(isResolved || isDropped ? .secondary : .primary)

            Spacer()

            statusBadge(item, isResolved: isResolved, isDropped: isDropped)

            if !isResolved {
                dropButton(itemID: itemID, isDropped: isDropped)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func statusBadge(_ item: CDStudentFocusItem, isResolved: Bool, isDropped: Bool) -> some View {
        if isResolved {
            badge("done today", warn: false)
        } else if isDropped {
            badge("dropped", warn: false)
        } else if let createdAt = item.createdAt {
            let weeks = weeksCarried(since: createdAt)
            if weeks > 0 {
                badge("\(weeks) week\(weeks == 1 ? "" : "s")", warn: weeks >= 4)
            }
        }
    }

    private func dropButton(itemID: UUID, isDropped: Bool) -> some View {
        Button {
            adaptiveWithAnimation {
                if isDropped {
                    draft.droppedFocusIDs.remove(itemID)
                } else {
                    draft.resolvedFocusIDs.remove(itemID)
                    draft.droppedFocusIDs.insert(itemID)
                }
            }
        } label: {
            Image(systemName: isDropped ? "arrow.uturn.backward" : "xmark")
                .font(.caption)
                .foregroundStyle(isDropped ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDropped ? "Keep" : "Drop")
    }

    private func badge(_ text: String, warn: Bool) -> some View {
        Text(text)
            .font(.caption.weight(warn ? .semibold : .regular))
            .foregroundStyle(warn ? AppColors.warning : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .capsuleFill(
                warn ? AppColors.warning.opacity(0.14) : Color.primary.opacity(UIConstants.OpacityConstants.light)
            )
    }

    // MARK: - Pending Item Row

    private func pendingItemRow(itemID: UUID) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "square")
                .foregroundStyle(.secondary)
                .font(.title3)

            TextField("Focus item…", text: $draft.pendingFocus.element(id: itemID, default: "", \.text))
                .textFieldStyle(.plain)

            badge("new", warn: false)

            Button {
                adaptiveWithAnimation {
                    draft.pendingFocus.removeAll { $0.id == itemID }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
        }
        .padding(.vertical, 3)
    }

    // MARK: - Add Item Row

    private var addItemRow: some View {
        HStack(spacing: 10) {
            Button {
                addNewItem(refocus: true)
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(.accent)
                    .font(.body.weight(.medium))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add focus")

            TextField("Add a focus for next week", text: $newItemText)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .focused($isNewItemFocused)
                .onSubmit { addNewItem(refocus: true) }
                .onChange(of: isNewItemFocused) { _, isFocused in
                    if !isFocused { addNewItem(refocus: false) }
                }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Helpers

    private func addNewItem(refocus: Bool) {
        let trimmed = newItemText.trimmed()
        guard !trimmed.isEmpty else { return }
        draft.pendingFocus.append(PendingFocusItem(text: trimmed))
        newItemText = ""
        if refocus {
            isNewItemFocused = true
        }
    }

    private func weeksCarried(since date: Date) -> Int {
        let components = AppCalendar.shared.dateComponents([.weekOfYear], from: date, to: Date())
        return max(0, components.weekOfYear ?? 0)
    }
}
