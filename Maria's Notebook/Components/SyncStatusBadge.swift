import SwiftUI

/// A compact sync status badge for navigation bars and toolbars.
/// Shows a small indicator with optional popover for details.
struct SyncStatusBadge: View {
    @Environment(\.dependencies) private var dependencies
    @State private var syncService: CloudKitSyncStatusService
    @State private var showingPopover = false
    
    init() {
        _syncService = State(wrappedValue: AppDependenciesKey.defaultValue.cloudKitSyncStatusService)
    }

    private var isCloudKitActive: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)
    }

    var body: some View {
        if isCloudKitActive {
            Button {
                showingPopover.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(syncService.syncHealth.color.opacity(UIConstants.OpacityConstants.moderate))
                        .frame(width: 28, height: 28)

                    Image(systemName: syncService.syncHealth.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(syncService.syncHealth.color)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("iCloud Sync Status")
            .popover(isPresented: $showingPopover) {
                SyncStatusPopover()
            }
        }
    }
}

/// Popover content showing sync status details
struct SyncStatusPopover: View {
    @Environment(\.dependencies) private var dependencies
    @State private var syncService: CloudKitSyncStatusService
    
    init() {
        _syncService = State(wrappedValue: AppDependenciesKey.defaultValue.cloudKitSyncStatusService)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status Header
            HStack(spacing: 8) {
                Image(systemName: syncService.syncHealth.icon)
                    .foregroundStyle(syncService.syncHealth.color)
                Text(syncService.syncHealth.displayText)
                    .font(.headline)
            }

            // Last Sync Time
            if let lastSync = syncService.lastSuccessfulSync {
                HStack(spacing: 4) {
                    Text("Last synced:")
                        .foregroundStyle(.secondary)
                    Text(lastSync, style: .relative)
                    Text("ago")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            // Error Message
            if case .error(let message) = syncService.syncHealth {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppColors.destructive)
                    .lineLimit(3)
            }

            Divider()

            // Sync Now Button
            Button {
                Task {
                    await syncService.syncNow()
                }
            } label: {
                HStack(spacing: 6) {
                    if syncService.isSyncing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text("Sync Now")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(syncService.isSyncing)
        }
        .padding()
        .frame(width: 200)
    }
}

#Preview("Badge") {
    SyncStatusBadge()
        .padding()
}

#Preview("Popover") {
    SyncStatusPopover()
}
