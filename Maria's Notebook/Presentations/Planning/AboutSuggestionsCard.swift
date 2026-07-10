// AboutSuggestionsCard.swift
// Small explanatory card rendered below the students-needing-lessons sidebar.
// Helps the guide build a mental model of how "Suggest Next" prioritizes.

import SwiftUI

struct AboutSuggestionsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            HStack(spacing: AppTheme.Spacing.xxsmall) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("About these suggestions")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            Text(
                "We prioritize lessons based on time since last presentation, "
                + "student readiness, and curriculum progression."
            )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }
}
