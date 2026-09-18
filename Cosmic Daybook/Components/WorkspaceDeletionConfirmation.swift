// WorkspaceDeletionConfirmation.swift
// One confirmation dialog, shared by both halves of the workspace.
//
// The dialog belongs to the *grid*, not to the card that raised it: a grid has
// one dialog with one count, and it survives the card scrolling out from under
// the pointer. Holding the pending records rather than a bare flag is what lets
// the dialog name what it is about to destroy.

import SwiftUI

struct WorkspaceDeletionConfirmation<Record>: ViewModifier {
    @Binding var pending: [Record]
    let title: String
    let confirmTitle: String
    let message: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(
                get: { !pending.isEmpty },
                set: { if !$0 { pending = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button(confirmTitle, role: .destructive) { onConfirm() }
            Button("Cancel", role: .cancel) { pending = [] }
        } message: {
            Text(message)
        }
    }
}

extension View {
    /// Confirms destroying `pending`, and clears it either way.
    func workspaceDeletionConfirmation<Record>(
        pending: Binding<[Record]>,
        title: String,
        confirmTitle: String,
        message: String,
        onConfirm: @escaping () -> Void
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
