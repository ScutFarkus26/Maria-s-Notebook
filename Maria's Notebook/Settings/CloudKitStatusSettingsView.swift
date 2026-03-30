import SwiftUI
import SwiftData

struct CloudKitStatusSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @State private var syncService: CloudKitSyncStatusService
    @State private var isSyncDetailsExpanded = false
    @AppStorage(UserDefaultsKeys.enableCloudKitSync) private var isCloudKitEnabled = true
    
    init() {
        _syncService = State(wrappedValue: AppDependenciesKey.defaultValue.cloudKitSyncStatusService)
    }

    private var isCloudKitActive: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)
    }

    private var recentErrorLogs: [CloudKitConfigurationService.ErrorLogEntry] {
        let logs = CloudKitConfigurationService.getErrorLogs()
        return Array(logs.suffix(3).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable iCloud Sync", isOn: $isCloudKitEnabled)

            if isCloudKitEnabled != isCloudKitActive {
                Text("Restart required for this change to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .rotationEffect(.degrees(syncService.isSyncing ? 360 : 0))
                            .adaptiveAnimation(
                                syncService.isSyncing
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default,
                                value: syncService.isSyncing
                            )
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

            if isCloudKitActive {
                syncDetailsSection
            }

            if !recentErrorLogs.isEmpty {
                recentErrorsSection
            }

            // Error Display
            if case .error(let message) = syncService.syncHealth {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.destructive)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppColors.destructive)
                        .lineLimit(3)

                    Spacer()

                    Button("Dismiss") {
                        syncService.clearError()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color.red.opacity(UIConstants.OpacityConstants.light))
                .cornerRadius(8)
            }
        }
    }

    private var syncDetailsSection: some View {
        DisclosureGroup("Sync Details", isExpanded: $isSyncDetailsExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                DetailRow(label: "Network", value: syncService.isNetworkAvailable ? "Online" : "Offline")
                DetailRow(label: "iCloud Account", value: syncService.isICloudAvailable ? "Available" : "Unavailable")
                DetailRow(label: "Current Operation", value: syncService.currentOperation ?? "Idle")
                DetailRow(label: "Pending Changes", value: "\(syncService.pendingLocalChanges)")
                DetailRow(
                    label: "Retry",
                    value: syncService.hasPendingRetry
                        ? "\(syncService.retryAttempt)/\(syncService.maxRetryAttempts) scheduled"
                        : "\(syncService.retryAttempt)/\(syncService.maxRetryAttempts)"
                )

                if let lastOperation = syncService.lastOperation {
                    DetailRow(label: "Last Operation", value: lastOperation)
                }

                if let lastOperationDate = syncService.lastOperationDate {
                    DetailRow(
                        label: "Last Operation Time",
                        value: lastOperationDate.formatted(date: .abbreviated, time: .standard)
                    )
                }
            }
            .padding(.top, 6)
        }
        .padding(.top, 4)
    }

    private var recentErrorsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent CloudKit Errors")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(Array(recentErrorLogs.enumerated()), id: \.offset) { _, log in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(log.category.displayName): \(log.errorMessage)")
                        .font(.caption)
                        .foregroundStyle(AppColors.destructive)
                        .lineLimit(3)

                    Text(log.category.recommendedAction)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(AppColors.destructive.opacity(UIConstants.OpacityConstants.subtle))
                .cornerRadius(6)
            }
        }
        .padding(.top, 4)
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
                return "Syncing your recent changes with iCloud now..."
            case .healthy, .unknown:
                return "Your data stays in sync with iCloud. New changes sync automatically across your devices."
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
                return "CloudKit sync failed to initialize."
                    + " Your data is stored locally and will NOT sync across devices."
                    + " Check your iCloud account and network connection, then restart the app."
            } else {
                return "iCloud sync is enabled but requires an app restart to take effect."
            }
        } else {
            return "Your data is stored locally on this device only."
                + " Enable iCloud sync to keep your data synchronized across devices."
        }
    }

    private var offlineDescription: String {
        if !syncService.isNetworkAvailable && !syncService.isICloudAvailable {
            return "No network connection and iCloud account unavailable."
                + " Changes are saved locally and will sync when both are restored."
        } else if !syncService.isNetworkAvailable {
            return "No network connection. Changes are saved locally and will sync when you're back online."
        } else if !syncService.isICloudAvailable {
            return "iCloud account unavailable. Sign in to iCloud in System Settings to sync your data."
        } else {
            return "Unable to connect to iCloud. Changes are saved locally and will sync when connection is restored."
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Animated sync status indicator
struct SyncStatusIndicator: View {
    let health: CloudKitHealthCheck.SyncHealth

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(health.color.opacity(UIConstants.OpacityConstants.moderate))
                .frame(width: 28, height: 28)

            Image(systemName: health.icon)
                .font(.system(size: 14))
                .foregroundStyle(health.color)
                .rotationEffect(.degrees(health == .syncing && isAnimating ? 360 : 0))
                .adaptiveAnimation(
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
