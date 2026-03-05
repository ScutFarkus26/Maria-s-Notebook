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
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
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
                .font(.subheadline.weight(.semibold))
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
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            SectionHeader(title: title, systemImage: systemImage)
            content
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

// MARK: - Reusable Authorization Section

/// A reusable component for displaying authorization request UI for system services
/// (Reminders, Calendar, etc.)
struct AuthorizationRequestSection: View {
    let serviceName: String
    let description: String
    let settingsPath: String
    let isRefreshing: Bool
    let statusMessage: String?
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(SettingsStyle.toggleScale)
                    Text("Requesting access...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Request Access") {
                    onRequestAccess()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let status = statusMessage {
                StatusMessageView(message: status)
            }

            Text("If denied, enable access in System Settings → Privacy & Security → \(settingsPath).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Status Message View

/// A reusable component for displaying status messages with appropriate coloring
struct StatusMessageView: View {
    let message: String
    var style: StatusStyle = .auto

    enum StatusStyle {
        case auto
        case success
        case error
        case info
    }

    private var color: Color {
        switch style {
        case .success:
            return .green
        case .error:
            return .red
        case .info:
            return .secondary
        case .auto:
            if message.contains("Error") || message.contains("Failed") || message.contains("denied") {
                return .red
            } else if message.contains("success") || message.contains("granted") || message.contains("completed") {
                return .green
            } else {
                return .secondary
            }
        }
    }

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(color)
    }
}

// MARK: - Sync Action Buttons

/// Reusable component for refresh/sync button pair used in sync settings
struct SyncActionButtons: View {
    let refreshLabel: String
    let syncLabel: String
    let isSyncDisabled: Bool
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onSync: () -> Void

    init(
        refreshLabel: String = "Refresh",
        syncLabel: String = "Sync Now",
        isSyncDisabled: Bool,
        isRefreshing: Bool,
        onRefresh: @escaping () -> Void,
        onSync: @escaping () -> Void
    ) {
        self.refreshLabel = refreshLabel
        self.syncLabel = syncLabel
        self.isSyncDisabled = isSyncDisabled
        self.isRefreshing = isRefreshing
        self.onRefresh = onRefresh
        self.onSync = onSync
    }

    var body: some View {
        HStack {
            Button(refreshLabel) {
                onRefresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button(syncLabel) {
                onSync()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isSyncDisabled || isRefreshing)
        }
    }
}

// MARK: - Last Sync Display

/// Reusable component for displaying last sync time
struct LastSyncView: View {
    let lastSync: Date?

    var body: some View {
        if let lastSync {
            Text("Last synced: \(lastSync, style: .relative) ago")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
                adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
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
                    .font(.subheadline.weight(.semibold))
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
