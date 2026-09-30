// SettingsDatabaseComponents.swift
// The collapsible sections and the total of Notebook at a glance.

import SwiftUI

// MARK: - Database Stats Subsection (Collapsible)

/// One section of Notebook at a glance, collapsed to its title and record count.
struct DatabaseStatsSubsection<Content: View>: View {
    let title: String
    let systemImage: String
    /// Records in this section, shown beside its title.
    let count: Int
    @ViewBuilder var content: Content

    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, AppTheme.Spacing.small)
        } label: {
            HStack(spacing: AppTheme.Spacing.small) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("^[\(count) record](inflect: true)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Database Total Summary

/// The notebook's record count, shown once above the sections.
struct DatabaseTotalSummary: View {
    let totalRecords: Int

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Label("Records across your notebook", systemImage: "books.vertical.fill")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(totalRecords, format: .number)
                .font(.title2.weight(.bold).monospacedDigit())
        }
        .padding(SettingsStyle.compactPadding)
        .surface(
            UIConstants.CornerRadius.control,
            fill: Color.accentColor.opacity(UIConstants.OpacityConstants.subtle),
            stroke: Color.accentColor.opacity(UIConstants.OpacityConstants.accent),
            style: .continuous
        )
        .accessibilityElement(children: .combine)
    }
}
