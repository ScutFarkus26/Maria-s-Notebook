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

    /// Standard toggle scale for consistency
    static let toggleScale: CGFloat = 0.8

    /// Standard spacing between sections
    static let sectionSpacing: CGFloat = 24

    /// Standard spacing within groups
    static let groupSpacing: CGFloat = 12

    /// Platform-specific background color for settings groups
    static var groupBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
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
        VStack(alignment: .center, spacing: 6) {
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
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
            Text(title)
                .font(.subheadline.weight(.bold))
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }
}

struct SettingsCategoryHeader: View {
    let title: String
    let systemImage: String?

    init(title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.top, 8)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    let collapsible: Bool
    let onReset: (() -> Void)?
    @ViewBuilder var content: Content

    @State private var isExpanded: Bool = true

    init(
        title: String,
        systemImage: String,
        collapsible: Bool = false,
        onReset: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.collapsible = collapsible
        self.onReset = onReset
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
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
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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

            if isExpanded || !collapsible {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(SettingsStyle.padding)
        .background(
            RoundedRectangle(cornerRadius: SettingsStyle.cornerRadius, style: .continuous)
                .fill(SettingsStyle.groupBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsStyle.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(SettingsStyle.borderOpacity))
        )
    }
}
