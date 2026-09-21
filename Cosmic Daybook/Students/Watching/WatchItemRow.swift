// WatchItemRow.swift
// One WatchList row, drawn the same way on the student page and on Today.

import SwiftUI

extension WatchItemKind {
    var tint: Color {
        switch self {
        case .flaggedNote: .orange
        case .watchTodo: .blue
        case .goal: .purple
        }
    }
}

/// Kind icon, text, when it was raised, and a due chip for todos. Tapping
/// opens the source; the "Clear" action is the caller's to attach (a swipe on
/// Today's list, a context menu on the student page).
struct WatchItemRow: View {
    let item: WatchItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(item.kind.tint)
                    .frame(width: 16)
                    .padding(.top, 2)
                    .accessibilityLabel(item.kind.title)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                    Text(item.text.isEmpty ? item.kind.title : item.text)
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: AppTheme.Spacing.small) {
                        Text(dateLabel)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                        if let dueDate = item.dueDate {
                            Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(item.kind.tint)
                                .padding(.horizontal, AppTheme.Spacing.verySmall)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(
                                        item.kind.tint.opacity(UIConstants.OpacityConstants.hint)
                                    )
                                )
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the \(item.kind.title.lowercased())")
    }

    private var dateLabel: String {
        guard item.date > .distantPast else { return "Undated" }
        return item.date.formatted(.relative(presentation: .named))
    }
}

/// The wording of the confirmation shown before clearing a note that names
/// more than one child: one flag covers all of them.
enum WatchClearConfirmation {
    static let title = "Clear this note's flag?"
    static let message = "It clears the flag for every child the note names."
    static let action = "Clear Flag"

    /// True when the row's note yields rows for other children too.
    static func isNeeded(for item: WatchItem, in all: [WatchItem]) -> Bool {
        guard item.kind == .flaggedNote, item.studentID != nil else { return false }
        return all.filter { $0.kind == .flaggedNote && $0.sourceID == item.sourceID }.count > 1
    }
}

extension View {
    /// The confirmation both Watching lists put up before clearing a flag that
    /// other children share. `item` is the row awaiting an answer.
    func watchClearConfirmation(_ item: Binding<WatchItem?>) -> some View {
        modifier(WatchClearConfirmationModifier(item: item))
    }
}

private struct WatchClearConfirmationModifier: ViewModifier {
    @Binding var item: WatchItem?
    @Environment(\.managedObjectContext) private var viewContext

    func body(content: Content) -> some View {
        content.confirmationDialog(
            WatchClearConfirmation.title,
            isPresented: Binding(
                get: { item != nil },
                set: { if !$0 { item = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(WatchClearConfirmation.action, role: .destructive) {
                if let pending = item { WatchListActions.clear(pending, in: viewContext) }
                item = nil
            }
        } message: {
            Text(WatchClearConfirmation.message)
        }
    }
}

private struct WatchItemRowPreview: View {
    var body: some View {
        List {
            WatchItemRow(
                item: WatchItem(
                    kind: .flaggedNote, sourceID: UUID(), studentID: UUID(),
                    text: "Etty kept restarting the stamp game rather than checking her carries.",
                    date: Date(), dueDate: nil
                ),
                onOpen: {}
            )
            WatchItemRow(
                item: WatchItem(
                    kind: .watchTodo, sourceID: UUID(), studentID: UUID(),
                    text: "Watch Ora with the checkerboard",
                    date: Date(), dueDate: AppCalendar.addingDays(3, to: Date())
                ),
                onOpen: {}
            )
            WatchItemRow(
                item: WatchItem(
                    kind: .goal, sourceID: UUID(), studentID: UUID(),
                    text: "Finish racks and tubes", date: .distantPast, dueDate: nil
                ),
                onOpen: {}
            )
        }
    }
}

#Preview {
    WatchItemRowPreview()
}
