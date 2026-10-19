// ParshaBrowseView.swift
// Column-2 view when the "Parshas" sentinel is selected in the areas column.
// The parsha lessons and the year's Shabbatot live on one screen, This Week's
// Parsha; this column points to it instead of listing them again.

import SwiftUI

struct ParshaBrowseView: View {
    /// The Go menu's route: this window switches screen, never another window.
    @Environment(\.quickCaptureActions) private var quickCapture

    var body: some View {
        ContentUnavailableView {
            Label("Parsha Lessons", systemImage: "book.closed")
        } description: {
            Text(
                "Lessons for each parsha are on the This Week’s Parsha screen. " +
                "The year’s Shabbatot are listed there too: beside the week on a Mac or iPad, " +
                "behind the Year button on an iPhone."
            )
        } actions: {
            Button {
                quickCapture?.go(to: .thisWeeksParsha)
            } label: {
                Label("Open This Week’s Parsha", systemImage: "book.closed")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
