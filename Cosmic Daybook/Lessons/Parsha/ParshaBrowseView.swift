// ParshaBrowseView.swift
// Column-2 view when the "Parshas" sentinel is selected in the areas column.
// The parsha lessons and the year's Shabbatot live on one screen, This Week's
// Parsha; this column points to it instead of listing them again.

import SwiftUI

struct ParshaBrowseView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Parsha Lessons", systemImage: "book.closed")
        } description: {
            Text(
                "Lessons for each parsha are on the This Week’s Parsha screen, " +
                "with every Shabbat of the year listed beside them."
            )
        } actions: {
            Button {
                AppRouter.shared.selectedNavItem = .thisWeeksParsha
            } label: {
                Label("Open This Week’s Parsha", systemImage: "book.closed")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
