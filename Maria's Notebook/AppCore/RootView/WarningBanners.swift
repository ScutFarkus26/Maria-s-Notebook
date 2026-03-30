// WarningBanners.swift
// Warning banners for store and sync issues

import SwiftUI

// MARK: - Ephemeral Store Warning Banner

/// Warning banner displayed when using ephemeral/in-memory store.
struct EphemeralStoreWarningBanner: View {
    @Environment(\.appRouter) private var appRouter

    private var reason: String {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.lastStoreErrorDescription)
        ?? "The persistent store could not be opened. Data will not persist this session."
    }

    private var isInMemoryMode: Bool {
        reason.contains("in-memory") || reason.contains("temporary")
    }

    private var warningTitle: String {
        isInMemoryMode ? "⚠️ SAFE MODE: CHANGES WILL NOT BE SAVED" : "Warning: Data won't persist this session"
    }

    private var warningMessage: String {
        isInMemoryMode
        ? "You are using an in-memory store. All data will be lost when you quit the app. Create a backup immediately!"
        : reason
    }

    private var iconColor: Color {
        isInMemoryMode ? .red : .yellow
    }

    private var titleColor: Color {
        isInMemoryMode ? .red : .primary
    }

    private var backgroundColor: AnyShapeStyle {
        isInMemoryMode ? AnyShapeStyle(Color.red.opacity(UIConstants.OpacityConstants.light)) : AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderColor: Color {
        isInMemoryMode ? Color.red.opacity(0.3) : Color.primary.opacity(UIConstants.OpacityConstants.light)
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
            Button {
                appRouter.requestCreateBackup()
            } label: {
                Label("Backup Now", systemImage: "externaldrive.badge.plus")
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

    private var isiCloudSignedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var errorDescription: String? {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
    }

    private var warningTitle: String {
        if !isiCloudSignedIn {
            return "⚠️ Not Signed Into iCloud"
        } else if let error = errorDescription, !error.isEmpty {
            return "⚠️ CloudKit Init Failed"
        } else {
            return "⚠️ iCloud Sync Issue"
        }
    }

    private var warningMessage: String {
        if !isiCloudSignedIn {
            return "Sign in to iCloud in System Settings to enable sync across devices."
        } else if let error = errorDescription, !error.isEmpty {
            return error
        } else {
            return "Sync is enabled but not currently active."
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isiCloudSignedIn ? "icloud.slash" : "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(warningTitle)
                    .font(AppTheme.ScaledFont.callout.weight(.bold))
                Text(warningMessage)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                appRouter.navigateTo(.settings)
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(UIConstants.OpacityConstants.medium))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.yellow.opacity(0.3)),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(warningTitle). \(warningMessage)")
        .accessibilityHint("Contains settings button")
    }
}
