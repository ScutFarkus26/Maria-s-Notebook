// ProgressionBatchActionBar.swift
// Floating bottom bar for batch actions on selected students.

import SwiftUI

/// Floating bottom bar when students are selected in the group progression matrix.
struct ProgressionBatchActionBar: View {
    let selectedCount: Int
    let onScheduleNext: () -> Void
    let onDeselectAll: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Student count badge
            Text("\(selectedCount) selected")
                .font(.subheadline.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.blue.opacity(0.15)))

            Spacer()

            Button {
                onScheduleNext()
            } label: {
                Label("Schedule Next Lesson", systemImage: SFSymbol.Time.calendar)
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button {
                onDeselectAll()
            } label: {
                Label("Deselect", systemImage: SFSymbol.Action.xmark)
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
