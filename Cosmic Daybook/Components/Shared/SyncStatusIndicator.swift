import SwiftUI

/// When the compact sync dot is worth a glance. A green "all synced" dot said
/// nothing, so the dot shows only while sync has something to say: syncing,
/// changes waiting to go up, an error, or no network.
enum SyncDotVisibility {
    static func isShown(
        isNetworkAvailable: Bool,
        isSyncing: Bool,
        pendingLocalChanges: Int,
        hasError: Bool
    ) -> Bool {
        !isNetworkAvailable || isSyncing || pendingLocalChanges > 0 || hasError
    }

    static func isShown(for service: CloudKitSyncStatusService) -> Bool {
        isShown(
            isNetworkAvailable: service.isNetworkAvailable,
            isSyncing: service.isSyncing,
            pendingLocalChanges: service.pendingLocalChanges,
            hasError: service.lastSyncError != nil
        )
    }
}

/// A compact sync status dot that observes CloudKit sync state.
/// Shows a colored dot with optional label text. Rendered only when CloudKit is enabled;
/// the compact dot also hides while sync is idle and fine (`SyncDotVisibility`).
struct CompactSyncStatusIndicator: View {
    let compact: Bool
    var syncService = CloudKitSyncStatusService.shared

    init(compact: Bool = false) {
        self.compact = compact
    }

    private var dotColor: Color {
        if !syncService.isNetworkAvailable {
            return .gray
        }
        if syncService.isSyncing || syncService.pendingLocalChanges > 0 {
            return .orange
        }
        if syncService.lastSyncError != nil {
            return .red
        }
        return .green
    }

    private var statusText: String {
        if !syncService.isNetworkAvailable {
            return "Offline"
        }
        if syncService.isSyncing {
            return "Syncing…"
        }
        let pending = syncService.pendingLocalChanges
        if pending > 0 {
            return "\(pending) pending"
        }
        if syncService.lastSyncError != nil {
            return "Sync error"
        }
        return "Synced"
    }

    var body: some View {
        let cloudStatus = CloudKitConfiguration.getCloudKitStatus()
        if cloudStatus.enabled {
            if compact {
                if SyncDotVisibility.isShown(for: syncService) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("iCloud sync status")
                        .accessibilityValue(statusText)
                        .help("iCloud: \(statusText)")
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(AppTheme.SemanticFont.metadata)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("iCloud sync: \(statusText)")
            }
        }
    }
}

#if os(macOS)
/// The window toolbar's sync dot. Its own `ToolbarContent`, so a sync state
/// flip re-reads this item alone, not RootView's body. The item never leaves
/// the toolbar — `.hidden` keeps its identity stable (an item inserted and
/// removed by an `if` desyncs toolbars sharing the identifier) — it is only
/// hidden in Sample Class, which never syncs, and while sync is idle and fine.
struct SyncStatusToolbarItem: ToolbarContent {
    let isSampleClass: Bool
    var syncService = CloudKitSyncStatusService.shared

    var body: some ToolbarContent {
        ToolbarItem(id: "syncStatus", placement: .primaryAction) {
            CompactSyncStatusIndicator(compact: true)
        }
        .hidden(isSampleClass || !SyncDotVisibility.isShown(for: syncService))
    }
}
#endif
