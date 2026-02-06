import SwiftUI
import SwiftData

struct CloudKitStatusSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @StateObject private var syncService: CloudKitSyncStatusService
    
    init() {
        _syncService = StateObject(wrappedValue: AppDependenciesKey.defaultValue.cloudKitSyncStatusService)
    }

    private var isCloudKitEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
    }

    private var isCloudKitActive: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status Indicator Row
            HStack(spacing: 10) {
                SyncStatusIndicator(health: syncService.syncHealth)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.headline)

                    if isCloudKitActive, let lastSync = syncService.lastSuccessfulSync {
                        Text("Last synced: \(lastSync, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Sync Now Button
                if isCloudKitActive {
                    Button {
                        Task {
                            await syncService.syncNow()
                        }
                    } label: {
                        if syncService.isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(syncService.isSyncing)
                    .help("Sync Now")
                }
            }

            // Status Description
            Text(statusDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)

            // Error Display
            if case .error(let message) = syncService.syncHealth {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)

                    Spacer()

                    Button("Dismiss") {
                        syncService.clearError()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private var statusText: String {
        if isCloudKitActive {
            switch syncService.syncHealth {
            case .syncing: return "Syncing..."
            case .healthy: return "iCloud Sync Active"
            case .warning: return "iCloud Sync Active"
            case .error: return "Sync Error"
            case .offline: return "Offline"
            case .unknown: return "iCloud Sync Active"
            }
        } else if isCloudKitEnabled {
            return "iCloud Sync Enabled (Restart Required)"
        } else {
            return "iCloud Sync Disabled"
        }
    }

    private var statusDescription: String {
        if isCloudKitActive {
            switch syncService.syncHealth {
            case .syncing:
                return "Syncing your data with iCloud..."
            case .healthy, .unknown:
                return "Your data is syncing with iCloud. Changes will sync across your devices."
            case .warning:
                return "iCloud sync is active but experiencing minor issues."
            case .error:
                return "There was a problem syncing with iCloud. Your data is safe locally."
            case .offline:
                return offlineDescription
            }
        } else if isCloudKitEnabled {
            if let errorDescription = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastStoreErrorDescription),
               !errorDescription.isEmpty {
                return "CloudKit sync failed to initialize. Your data is stored locally and will NOT sync across devices. Check your iCloud account and network connection, then restart the app."
            } else {
                return "iCloud sync is enabled but requires an app restart to take effect."
            }
        } else {
            return "Your data is stored locally on this device only. Enable iCloud sync to keep your data synchronized across devices."
        }
    }

    private var offlineDescription: String {
        if !syncService.isNetworkAvailable && !syncService.isICloudAvailable {
            return "No network connection and iCloud account unavailable. Changes are saved locally and will sync when both are restored."
        } else if !syncService.isNetworkAvailable {
            return "No network connection. Changes are saved locally and will sync when you're back online."
        } else if !syncService.isICloudAvailable {
            return "iCloud account unavailable. Sign in to iCloud in System Settings to sync your data."
        } else {
            return "Unable to connect to iCloud. Changes are saved locally and will sync when connection is restored."
        }
    }
}

/// Animated sync status indicator
struct SyncStatusIndicator: View {
    let health: CloudKitSyncStatusService.SyncHealth

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(health.color.opacity(0.2))
                .frame(width: 28, height: 28)

            Image(systemName: health.icon)
                .font(.system(size: 14))
                .foregroundStyle(health.color)
                .rotationEffect(.degrees(health == .syncing && isAnimating ? 360 : 0))
                .animation(
                    health == .syncing
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .default,
                    value: isAnimating
                )
        }
        .onChange(of: health) { _, newHealth in
            if newHealth == .syncing {
                isAnimating = true
            }
        }
        .onAppear {
            if health == .syncing {
                isAnimating = true
            }
        }
    }
}

#Preview {
    CloudKitStatusSettingsView()
}
