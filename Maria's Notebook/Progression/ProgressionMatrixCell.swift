// ProgressionMatrixCell.swift
// Colored dot cell for the group progression matrix.

import SwiftUI

/// A tapable colored dot cell representing a student's status for a specific lesson.
struct ProgressionMatrixCell: View {
    let status: GroupCellStatus
    let lessonName: String
    let studentName: String

    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover = true
        } label: {
            Circle()
                .fill(status.color.opacity(status == .notStarted ? 0.3 : 1.0))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(studentName): \(lessonName) – \(status.label)")
        .popover(isPresented: $isShowingPopover) {
            VStack(alignment: .leading, spacing: 8) {
                Text(lessonName)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 10, height: 10)
                    Text(status.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(studentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 180)
        }
    }
}
