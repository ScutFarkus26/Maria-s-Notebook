import SwiftUI

// MARK: - Settings Styling Constants

/// Unified styling constants for settings views
enum SettingsStyle {
    /// Standard corner radius for settings cards (matches SettingsGroup)
    static let cornerRadius: CGFloat = 16

    /// Standard padding for settings cards
    static let padding: CGFloat = 16

    /// Compact padding for grid cards
    static let compactPadding: CGFloat = 12

    /// Standard spacing between sections
    static let sectionSpacing: CGFloat = 24

    /// Standard spacing within groups
    static let groupSpacing: CGFloat = 12

    /// Platform-specific background color for settings groups
    static var groupBackgroundColor: Color {
        Color.controlBackgroundColor()
    }

    /// Border opacity for settings cards
    static let borderOpacity: Double = 0.06
}

// MARK: - Shared Settings UI Components

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        VStack(alignment: .center, spacing: AppTheme.Spacing.verySmall) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text(subtitle ?? " ")
                .font(.subheadline)
                .foregroundStyle(subtitle?.isEmpty == false ? Color.secondary : Color.clear)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxWidth: .infinity, minHeight: 120)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
            Text(title)
                .font(.subheadline.weight(.bold))
        }
        .textCase(nil)
        .padding(.bottom, AppTheme.Spacing.xxsmall)
    }
}

/// The open pane's title, beside its category's colored tile.
struct SettingsCategoryHeader: View {
    let category: SettingsCategory

    var body: some View {
        HStack(spacing: 10) {
            SettingsCategoryIcon(category: category, size: 30)
            Text(category.displayName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.top, AppTheme.Spacing.small)
        .background {
            CosmicHeaderAccent()
                .padding(-AppTheme.Spacing.small)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    let collapsible: Bool
    let footer: String?
    let anchorID: String?
    let onReset: (() -> Void)?
    @ViewBuilder var content: Content

    @State private var isExpanded: Bool = true
    /// The card a search just jumped to; this card outlines itself while it's this one.

    /// A card named in `SettingsCopy`, which search can find and scroll to.
    init(
        _ group: SettingsCopy.Group,
        collapsible: Bool = false,
        footer: String? = nil,
        onReset: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = group.title
        self.systemImage = group.systemImage
        self.collapsible = collapsible
        self.footer = footer
        self.anchorID = group.anchorID
        self.onReset = onReset
        self.content = content()
    }

    /// A card inside a pane's own layout, which search doesn't list on its own.
    init(
        title: String,
        systemImage: String,
        collapsible: Bool = false,
        footer: String? = nil,
        onReset: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.collapsible = collapsible
        self.footer = footer
        self.anchorID = nil
        self.onReset = onReset
        self.content = content()
    }

    var body: some View {
        card
            .settingsAnchor(anchorID)
    }

    @ViewBuilder
    private var card: some View {
        #if os(macOS)
        GroupBox {
            if isExpanded || !collapsible {
                expandedContent
                    .padding(.top, AppTheme.Spacing.xsmall)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } label: {
            groupHeader
        }
        #else
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            groupHeader

            if isExpanded || !collapsible {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(SettingsStyle.padding)
        .surface(
            SettingsStyle.cornerRadius,
            fill: SettingsStyle.groupBackgroundColor,
            stroke: Color.primary.opacity(SettingsStyle.borderOpacity),
            style: .continuous
        )
        #endif
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            content
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var groupHeader: some View {
        HStack {
            if collapsible {
                Button {
                    adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        SectionHeader(title: title, systemImage: systemImage)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            } else {
                SectionHeader(title: title, systemImage: systemImage)
                Spacer()
            }

            if let onReset {
                Menu {
                    Button(role: .destructive) {
                        onReset()
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }
        }
    }
}

/// A row inside a card that opens another screen: icon, title, chevron.
struct SettingsLinkRow: View {
    let title: String
    let systemImage: String
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer()
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .contentShape(Rectangle())
    }
}
