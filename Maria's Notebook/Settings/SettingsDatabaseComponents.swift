// SettingsDatabaseComponents.swift
// Collapsible database stats subsection and total summary components for Settings.

import SwiftUI

// MARK: - Database Stats Subsection (Collapsible)

/// A collapsible subsection for grouping database stats within the Database section
struct DatabaseStatsSubsection<Content: View>: View {
    let title: String
    let systemImage: String
    let summaryValue: String
    @ViewBuilder var content: Content

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                _ = adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(summaryValue)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Database Total Summary

/// Displays total record count with a progress-style bar
struct DatabaseTotalSummary: View {
    let totalRecords: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cylinder.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Records")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text("\(totalRecords) records across all entities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(totalRecords)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(SettingsStyle.compactPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.15))
        )
    }
}
