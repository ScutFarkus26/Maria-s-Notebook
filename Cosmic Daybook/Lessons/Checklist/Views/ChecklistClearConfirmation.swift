// ChecklistClearConfirmation.swift
// The question Clear asks when the cells hold history (`ChecklistClearSummary`). It waits
// for the cell's card to close first (`afterClosingCard`), since an alert can't show over
// the card's popover or sheet.

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
