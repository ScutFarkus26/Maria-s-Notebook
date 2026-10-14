import SwiftUI

/// What the sync dot says. It follows the per-store health and the stopped
/// flag too: the classroom share can stop while the notebook syncs, and the
/// one shown error is cleared by the notebook's successes, so the dot used to
/// read fine while Settings said the share was stopped.
enum SyncDotState: Equatable {
    case offline
    case signedOut
    /// A store's sync is stopped until someone acts; red even while the other syncs.
    case stopped
    case syncing
    case waiting(Int)
    case problem
    case synced

    var color: Color {
        switch self {
        case .offline, .signedOut: return .gray
        case .stopped, .problem: return .red
        case .syncing, .waiting: return .orange
        case .synced: return .green
        }
    }

    var text: String {
        switch self {
        case .offline: return "Offline"
        case .signedOut: return "iCloud isn't available"
        case .stopped: return "Sync is stopped \u{2014} see Settings"
        case .syncing: return "Syncing…"
        case .waiting(let count): return count == 1 ? "1 change waiting to send" : "\(count) changes waiting to send"
        case .problem: return "Sync problem \u{2014} see Settings"
        case .synced: return "Synced"
        }
    }
}

/// When the compact sync dot is worth a glance. A green "all synced" dot said
/// nothing, so the dot shows only while sync has something to say: syncing,
/// changes waiting to go up, an error or a store failure, or no network or account.
enum SyncDotVisibility {
    // swiftlint:disable:next function_parameter_count
    static func state(
        isNetworkAvailable: Bool,
        isSignedOut: Bool,
        isStopped: Bool,
        isSyncing: Bool,
        pendingLocalChanges: Int,
        hasError: Bool
    ) -> SyncDotState {
        if !isNetworkAvailable { return .offline }
        if isSignedOut { return .signedOut }
        if isStopped { return .stopped }
        if isSyncing { return .syncing }
        if pendingLocalChanges > 0 { return .waiting(pendingLocalChanges) }
        if hasError { return .problem }
        return .synced
    }

    static func state(for service: CloudKitSyncStatusService) -> SyncDotState {
        let failure = service.storeHealth.mostSevereFailure
        return state(
            isNetworkAvailable: service.isNetworkAvailable,
            isSignedOut: service.isICloudSignedOut,
            isStopped: service.mirroringDelegateFailed || failure?.severity == .stopped,
            isSyncing: service.isSyncing,
            pendingLocalChanges: service.pendingLocalChanges,
            hasError: service.lastSyncError != nil || failure != nil
        )
    }

    static func isShown(
        isNetworkAvailable: Bool,
        isSyncing: Bool,
        pendingLocalChanges: Int,
        hasError: Bool
    ) -> Bool {
        state(
            isNetworkAvailable: isNetworkAvailable, isSignedOut: false, isStopped: false,
            isSyncing: isSyncing, pendingLocalChanges: pendingLocalChanges, hasError: hasError
        ) != .synced
    }

    static func isShown(for service: CloudKitSyncStatusService) -> Bool {
        state(for: service) != .synced
    }
}

/// The compact dot itself. It always lays out its 8-pt circle and only fades, so showing or
/// hiding it never resizes what sits beside it (it used to come and go with `if`, which
/// shoved the toolbar around every time sync started or finished).
struct SyncDotView: View {
    let state: SyncDotState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isShown = state != .synced
        Circle()
            .fill(state.color)
            .frame(width: 8, height: 8)
            .opacity(isShown ? 1 : 0)
            // One soft fade, never a pulse. Under Reduce Motion it just appears.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isShown)
            .accessibilityElement()
            .accessibilityLabel("iCloud sync status")
            .accessibilityValue(state.text)
            .accessibilityHidden(!isShown)
            .help(isShown ? "iCloud: \(state.text)" : "")
    }
}

/// A compact sync status dot that observes CloudKit sync state.
/// Shows a colored dot with optional label text. Rendered only when CloudKit is enabled;
/// the compact dot fades out while sync is idle and fine (`SyncDotVisibility`).
struct CompactSyncStatusIndicator: View {
    let compact: Bool
    var syncService = CloudKitSyncStatusService.shared

    init(compact: Bool = false) {
        self.compact = compact
    }

    var body: some View {
        let cloudStatus = CloudKitConfiguration.getCloudKitStatus()
        if cloudStatus.enabled {
            let state = SyncDotVisibility.state(for: syncService)
            if compact {
                SyncDotView(state: state)
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.color)
                        .frame(width: 8, height: 8)
                    Text(state.text)
                        .font(AppTheme.SemanticFont.metadata)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("iCloud sync: \(state.text)")
            }
        }
    }
}

#if os(macOS)
/// The window toolbar's sync dot. Its own `ToolbarContent`, so a sync state
/// flip re-reads this item alone, not RootView's body. The item never leaves
/// the toolbar — `.hidden` keeps its identity stable (an item inserted and
/// removed by an `if` desyncs toolbars sharing the identifier) — it is only
/// hidden in Sample Class, which never syncs. While sync is idle and fine the dot
/// fades to clear inside its fixed slot, and the item has no glass of its own, so
/// showing it can't resize the capsule around its neighbors.
struct SyncStatusToolbarItem: ToolbarContent {
    let isSampleClass: Bool

    var body: some ToolbarContent {
        ToolbarItem(id: "syncStatus", placement: .primaryAction) {
            CompactSyncStatusIndicator(compact: true)
        }
        .sharedBackgroundVisibility(.hidden)
        .hidden(isSampleClass)
    }
}
#endif
