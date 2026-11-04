// ChecklistClearConfirmation.swift
// The question Clear asks when the cells hold history (`ChecklistClearSummary`), and the
// one Unmark Presented and Remove Plan ask before deleting a record (`ChecklistRemovalRequest`).
// Each waits for the cell's card to close first (`afterClosingCard`), since an alert can't
// show over the card's popover or sheet.

import CoreData
import SwiftUI

struct ChecklistClearConfirmation: ViewModifier {
    let viewModel: ClassAreaChecklistViewModel
    let context: NSManagedObjectContext
    let afterClosingCard: (@escaping () -> Void) -> Void

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.pendingClear) { _, request in
                guard request != nil else { return }
                afterClosingCard { isPresented = viewModel.pendingClear != nil }
            }
            // However the alert goes away, the question is over; Clear acts on the
            // request it was shown, so the order of the two doesn't matter.
            .onChange(of: isPresented) { _, shown in
                if !shown { viewModel.cancelClear() }
            }
            .alert(
                viewModel.pendingClear?.title ?? "",
                isPresented: $isPresented,
                presenting: viewModel.pendingClear
            ) { request in
                Button("Clear", role: .destructive) { viewModel.confirmClear(request, context: context) }
                Button("Cancel", role: .cancel) { viewModel.cancelClear() }
            } message: { request in
                Text(request.message)
            }
    }
}

/// The question Unmark Presented and Remove Plan ask when taking the child off would
/// delete a given presentation, or a plan with notes on it (`ChecklistRemovalRequest`),
/// shown the same way as Clear's.
struct ChecklistRemovalConfirmation: ViewModifier {
    let viewModel: ClassAreaChecklistViewModel
    let context: NSManagedObjectContext
    let afterClosingCard: (@escaping () -> Void) -> Void

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.pendingRemoval) { _, request in
                guard request != nil else { return }
                afterClosingCard { isPresented = viewModel.pendingRemoval != nil }
            }
            .onChange(of: isPresented) { _, shown in
                if !shown { viewModel.cancelRemoval() }
            }
            .alert(
                viewModel.pendingRemoval?.title ?? "",
                isPresented: $isPresented,
                presenting: viewModel.pendingRemoval
            ) { request in
                Button(request.summary.confirmLabel, role: .destructive) {
                    viewModel.confirmRemoval(request, context: context)
                }
                Button("Cancel", role: .cancel) { viewModel.cancelRemoval() }
            } message: { request in
                Text(request.message)
            }
    }
}
