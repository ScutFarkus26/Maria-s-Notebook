// WarningBanners.swift
// Warning banners for store and sync issues

import CloudKit
import SwiftUI

// MARK: - Ephemeral Store Warning Banner

/// Warning banner displayed when using ephemeral/in-memory store.
struct EphemeralStoreWarningBanner: View {
    @Environment(\.appRouter) private var appRouter
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    /// Read from the flag the launch sets when it falls back to an in-memory
    /// store, not from the stored reason's wording (which is free to change).
    private var isInMemoryMode: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.inMemoryStoreSession)
    }

    private var warningTitle: String {
        isInMemoryMode ? "Changes Won't Be Saved" : "Changes Might Not Be Saved"
    }

    private var warningMessage: String {
        isInMemoryMode
        ? "Your notebook couldn't be opened, so anything you change now will be lost when you quit. "
            + "Back up now, then reopen the app."
        : "Your notebook couldn't be opened normally this time. Back up now, then reopen the app."
    }

    private var iconColor: Color {
        isInMemoryMode ? .red : .yellow
    }

    private var titleColor: Color {
        isInMemoryMode ? .red : .primary
    }

    private var backgroundColor: AnyShapeStyle {
        isInMemoryMode
            ? AnyShapeStyle(Color.red.opacity(UIConstants.OpacityConstants.light))
            : AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderColor: Color {
        isInMemoryMode
            ? Color.red.opacity(UIConstants.OpacityConstants.semi)
            : Color.primary.opacity(UIConstants.OpacityConstants.light)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(warningTitle)
                    .font(AppTheme.ScaledFont.callout.weight(.bold))
                    .foregroundStyle(titleColor)
                Text(warningMessage)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Opens Settings › Sync and backup, whose Back Up Now does it and
            // says how it went; the route this used to post went nowhere.
            Button {
                appRouter.showSyncBackupSettings()
                #if os(macOS)
                openSettings()
                #endif
            } label: {
                Label("Back Up…", systemImage: "externaldrive.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isInMemoryMode ? .red : nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(borderColor),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(warningTitle). \(warningMessage)")
        .accessibilityHint("Contains backup button")
    }
}

// MARK: - CloudKit Sync Warning Banner

/// Warning banner displayed when CloudKit sync is enabled but not active.
struct CloudKitSyncWarningBanner: View {
    @Environment(\.appRouter) private var appRouter

    /// CloudKit account availability. Defaults to true so the harsher
    /// "Not Signed Into iCloud" variant never flashes before the async check
    /// lands. Checked via CKContainer.accountStatus — the CloudKit API — not
    /// `ubiquityIdentityToken`, which reports iCloud *Drive* identity and is
    /// nil for users who disabled iCloud Drive while CloudKit sync still works.
    @State private var isiCloudSignedIn = true

    private var errorDescription: String? {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
    }

    private var warningTitle: String {
        if !isiCloudSignedIn {
            return "Not Signed In to iCloud"
        } else if let error = errorDescription, !error.isEmpty {
            return "iCloud Sync Couldn't Start"
        } else {
            return "iCloud Sync Isn't Running"
        }
    }

    /// The stored error is raw system text; it stays in the log and
    /// Troubleshooting's diagnostics, never in the banner.
    private var warningMessage: String {
        if !isiCloudSignedIn {
            return "Sign in to iCloud in \(SystemSettingsApp.name) to sync your notebook across your devices."
        } else if let error = errorDescription, !error.isEmpty {
            return "Your notebook is on this device and syncs again once iCloud reconnects. "
                + "Reopen the app to try again."
        } else {
            return "Sync is turned on but isn't running right now. Reopen the app to start it."
        }
    }

    var body: some View {
        bannerContent
            .task {
                if let status = try? await CloudKitConfigurationService.container.accountStatus() {
                    isiCloudSignedIn = status == .available
                }
            }
    }

    private var bannerContent: some View {
        let iconName: String = isiCloudSignedIn ? "icloud.slash" : "person.crop.circle.badge.exclamationmark"
        let title: String = warningTitle
        let message: String = warningMessage

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.ScaledFont.callout.weight(.bold))
                Text(message)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            settingsButton
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(UIConstants.OpacityConstants.medium))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.yellow.opacity(UIConstants.OpacityConstants.semi)),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityHint("Contains settings button")
    }

    /// The Mac keeps Settings in its own window (it has no sidebar row), so
    /// the button opens that; elsewhere Settings is a destination.
    @ViewBuilder
    private var settingsButton: some View {
        #if os(macOS)
        SettingsLink {
            Label("Settings", systemImage: "gear")
        }
        #else
        Button {
            appRouter.navigateTo(.settings)
        } label: {
            Label("Settings", systemImage: "gear")
        }
        #endif
    }
}
