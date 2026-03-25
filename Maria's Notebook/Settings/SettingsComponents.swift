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
                        _ = adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
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

// MARK: - Settings Toggle Row

/// A standardized toggle row for settings with consistent styling
struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(SettingsStyle.toggleScale)
                .labelsHidden()
        }
        .padding(.horizontal, SettingsStyle.compactPadding)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Template Card (for card-based template display)

/// A card-based template display that matches the SettingsGroup styling
struct TemplateCard: View {
    let title: String
    let subtitle: String
    let isBuiltIn: Bool
    let isActive: Bool
    let color: Color
    let onTap: () -> Void

    init(
        title: String,
        subtitle: String,
        isBuiltIn: Bool = false,
        isActive: Bool = false,
        color: Color = .accentColor,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isBuiltIn = isBuiltIn
        self.isActive = isActive
        self.color = color
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Color/status indicator
                Circle()
                    .fill(isActive ? Color.green : color)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isActive {
                            Text("Active")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AppColors.success.opacity(0.15)))
                                .foregroundStyle(AppColors.success)
                        }
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isBuiltIn {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(SettingsStyle.compactPadding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsStyle.groupBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(SettingsStyle.borderOpacity))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overview Grid

struct OverviewStatsGrid: View {
    let studentsCount: Int
    let lessonsCount: Int
    let plannedCount: Int
    let givenCount: Int
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            StatCard(title: "Students", value: String(studentsCount), subtitle: nil, systemImage: "person.3.fill")
            StatCard(title: "Lessons", value: String(lessonsCount), subtitle: nil, systemImage: "text.book.closed.fill")
            StatCard(
                title: "Lessons Planned", value: String(plannedCount),
                subtitle: nil, systemImage: "books.vertical.fill"
            )
            StatCard(
                title: "Lessons Given", value: String(givenCount),
                subtitle: nil, systemImage: "checkmark.circle.fill"
            )
        }
    }
}
