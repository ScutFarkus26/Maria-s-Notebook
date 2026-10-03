// SettingsAuthComponents.swift
// Authorization, status, and sync UI components for Settings views.

import SwiftUI

// MARK: - The Device's Settings App

/// The device's own settings app, named the way each platform names it, for every
/// "turn it on in …" or "sign in in …" message.
nonisolated enum SystemSettingsApp {
    /// "System Settings" on the Mac, "Settings" on iPhone and iPad.
    static var name: String {
        #if os(macOS)
        "System Settings"
        #else
        "Settings"
        #endif
    }

    /// The path to a privacy pane, e.g. "Settings › Privacy & Security › Calendars".
    static func privacyPath(_ pane: String) -> String {
        "\(name) › Privacy & Security › \(pane)"
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
    let statusMessage: StatusMessage?
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isRefreshing {
                HStack(spacing: AppTheme.Spacing.small) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Asking for access…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Request access") {
                    onRequestAccess()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let statusMessage {
                StatusMessageView(status: statusMessage)
            }

            Text("If you turned access off before, turn it back on in \(SystemSettingsApp.privacyPath(settingsPath)).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Status Message View

/// A one-line result shown under a sync panel's buttons. The caller says whether
/// it went well; the color follows from that, never from the wording.
struct StatusMessage: Equatable {
    enum Kind {
        case success
        case failure
        case info
    }

    let text: String
    let kind: Kind

    static func success(_ text: String) -> StatusMessage { StatusMessage(text: text, kind: .success) }
    static func failure(_ text: String) -> StatusMessage { StatusMessage(text: text, kind: .failure) }
    static func info(_ text: String) -> StatusMessage { StatusMessage(text: text, kind: .info) }
}

/// Shows a `StatusMessage` in its kind's color.
struct StatusMessageView: View {
    let status: StatusMessage

    private var color: Color {
        switch status.kind {
        case .success: return AppColors.success
        case .failure: return AppColors.destructive
        case .info: return .secondary
        }
    }

    var body: some View {
        Text(status.text)
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
        syncLabel: String = "Sync now",
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
            Text("Last synced: \(lastSync.formatted(.relative(presentation: .named)))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
