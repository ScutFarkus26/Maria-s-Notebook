//
//  WorkItemCompactRow.swift
//  Maria's Notebook
//
//  Compact row for displaying work items
//

import SwiftUI
import SwiftData

struct WorkItemCompactRow: View {
    let work: WorkModel
    let modelContext: ModelContext

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(work.status.color.opacity(UIConstants.OpacityConstants.accent))
                    .frame(width: 36, height: 36)

                Image(systemName: work.status.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(work.status.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(work.title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    if let student = work.fetchStudent(from: modelContext) {
                        Text(StudentFormatter.displayName(for: student))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let kind = work.kind {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(kind.rawValue)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Status badge
            Text(work.status.rawValue.capitalized)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(work.status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(work.status.color.opacity(UIConstants.OpacityConstants.medium))
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle), lineWidth: 1)
        )
    }
}
