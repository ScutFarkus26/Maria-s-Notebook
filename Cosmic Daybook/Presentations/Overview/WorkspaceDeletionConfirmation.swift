// WorkspaceDeletionConfirmation.swift
// One confirmation dialog, shared by both halves of the workspace.
//
// The dialog belongs to the *grid*, not to the card that raised it: a grid has
// one dialog with one count, and it survives the card scrolling out from under
// the pointer. Holding the pending records rather than a bare flag is what lets
// the dialog name what it is about to destroy.
//
// The records travel with the dialog as its `presenting:` data and reach
// `onConfirm` as an argument: the dialog's binding clears `pending` when it
// dismisses, and Apple doesn't say whether that happens before or after the
// button's action runs, so an action reading `pending` could find it empty and
// delete nothing (G1, bug hunt 2026-10-12).

import SwiftUI

struct WorkspaceDeletionConfirmation<Record>: ViewModifier {
    @Binding var pending: [Record]
    let title: String
    let confirmTitle: String
    let message: String
    let onConfirm: ([Record]) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(
                get: { !pending.isEmpty },
                set: { if !$0 { pending = [] } }
            ),
            titleVisibility: .visible,
            presenting: pending.isEmpty ? nil : pending
        ) { records in
            Button(confirmTitle, role: .destructive) {
                pending = []
                onConfirm(records)
            }
            Button("Cancel", role: .cancel) { pending = [] }
        } message: { _ in
            Text(message)
        }
    }
}

extension View {
    /// Confirms destroying `pending`, and clears it either way. `onConfirm`
    /// gets the records the dialog was shown for.
    func workspaceDeletionConfirmation<Record>(
        pending: Binding<[Record]>,
        title: String,
        confirmTitle: String,
        message: String,
        onConfirm: @escaping ([Record]) -> Void
    ) -> some View {
        modifier(WorkspaceDeletionConfirmation(
            pending: pending,
            title: title,
            confirmTitle: confirmTitle,
            message: message,
            onConfirm: onConfirm
        ))
    }
}
