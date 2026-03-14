// SettingsAuthComponents.swift
// Authorization, status, and sync UI components for Settings views.

import SwiftUI

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
