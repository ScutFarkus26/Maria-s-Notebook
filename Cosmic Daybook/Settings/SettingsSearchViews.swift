import SwiftUI

// MARK: - Sidebar Search Field

/// The search field above the wide layout's sidebar.
struct SettingsSidebarSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(AppTheme.Spacing.small)
        .surface(
            UIConstants.CornerRadius.medium,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.trace),
            style: .continuous
        )
    }
}

// MARK: - Search Result Row

/// A card that matches the search, listed under its category on iPhone.
struct SettingsSearchResultRow: View {
    let group: SettingsCopy.Group

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: group.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(group.title)
                Text(group.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, AppTheme.Spacing.medium)
        .accessibilityElement(children: .combine)
    }
}
