import SwiftUI

/// A compact sync status dot that observes CloudKit sync state.
/// Shows a colored dot with optional label text. Rendered only when CloudKit is enabled.
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
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("iCloud sync status")
                    .accessibilityValue(statusText)
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
