//
//  MCPNotebookTools+SyncStatus.swift
//  Cosmic Daybook
//
//  Whether the notebook is actually reaching iCloud.
//
//  This is the one operational question a guide asks that no amount of reading
//  records can answer: everything can look present locally while nothing has
//  left the device. `CloudKitSyncStatusService.shared` is the same source the
//  Settings pane reads, so this agrees with what the app shows.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    static func syncStatusTool() -> MCPToolDefinition {
        MCPToolDefinition(
            name: "sync_status",
            title: "Sync Status",
            description: "Whether the notebook is syncing to iCloud: overall health, each store "
                + "(the notebook and the classroom share) with its last success or the server's own "
                + "error, how many local changes are still waiting, and any error. "
                + "Use this when the guide asks whether their data is safe or why a device "
                + "looks out of date.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .readOnly,
            handler: { _ in
                describeSyncStatus()
            }
        )
    }

    static func describeSyncStatus(_ service: CloudKitSyncStatusService = .shared) -> String {
        var lines: [String] = ["Sync: \(healthLabel(service.syncHealth))"]
        lines += storeLines(service.storeHealth)

        if let last = service.lastSuccessfulSync {
            lines.append("  Last successful sync (any store): \(dayString(last)) at \(timeString(last))")
        } else {
            lines.append("  No successful sync recorded this session.")
        }

        let pending: Int = service.pendingLocalChanges
        lines.append(pending == 0
            ? "  No local changes waiting to upload."
            : "  \(pending) local change(s) still waiting to upload.")

        if !service.isNetworkAvailable {
            lines.append("  The device is offline.")
        }
        if !service.isICloudAvailable {
            lines.append("  iCloud is unavailable — check the account in System Settings.")
        }
        if service.hasPendingRetry {
            lines.append("  A retry is scheduled (attempt \(service.retryAttempt) of \(service.maxRetryAttempts)).")
        }
        // Claude gets the raw form (the app shows the plain one).
        if let error = nonEmpty(service.lastSyncErrorDetail) ?? nonEmpty(service.lastSyncError) {
            lines.append("  Last error: \(error)")
        }
        // A failed mirroring delegate is terminal for the process, so it must
        // not be buried; the advice says which store and whether re-downloading
        // helps (it doesn't when the server refused the store's changes).
        if service.mirroringDelegateFailed {
            let advice = SyncStoppedAdvice.make(health: service.storeHealth)
            let details = advice.details.isEmpty ? "" : " Details: \(advice.details)"
            lines.append("  WARNING: \(advice.title). \(advice.message)\(details)")
        }
        // A CloudKit setup failed for want of a ready iCloud account.
        switch service.shareFilingHold {
        case .untilReopen:
            lines.append("  Filing into the classroom share is paused until the app is reopened: a CloudKit setup "
                + "failed and no iCloud account is signed in. " + CloudKitSyncStatusService.shareFilingPausedMessage)
        case .untilICloudReady:
            let stores = service.accountNotReadyStores.count
            lines.append("  Filing into the classroom share waits for iCloud: \(stores) store(s) failed setup before "
                + "the account was ready; the hold lifts once each sets up and syncs again. "
                + CloudKitSyncStatusService.shareFilingWaitsForICloudMessage)
        case nil:
            break
        }
        return lines.joined(separator: "\n")
    }

    /// One line per store that has reported this session: its outstanding
    /// failures (quoting the server), else when it last finished an event.
    /// A store can stop while the other keeps syncing, so neither speaks for both.
    private static func storeLines(_ health: CloudKitStoreHealth) -> [String] {
        health.knownStores.flatMap { store -> [String] in
            let failures = health.failures(for: store)
            guard !failures.isEmpty else {
                guard let last = health.lastSuccess[store] else { return [] }
                return ["  \(store.displayName): OK, last synced \(dayString(last)) at \(timeString(last))."]
            }
            return failures.map { failure in
                let state = failure.severity == .stopped ? "NOT SYNCING" : "retrying"
                return "  \(store.displayName): \(state) since \(dayString(failure.date)) at "
                    + "\(timeString(failure.date)) — \(failure.eventName) failed: "
                    + "\u{201C}\(failure.serverMessage)\u{201D} (\(failure.errorCode))."
            }
        }
    }

    private static func healthLabel(_ health: CloudKitHealthCheck.SyncHealth) -> String {
        switch health {
        case .healthy: return "healthy"
        case .syncing: return "syncing now"
        case .warning: return "warning — syncing, but slowly or with minor issues"
        case .error(let message): return "error — \(message)"
        case .offline: return "offline"
        case .unknown: return "unknown (still starting up)"
        }
    }
}
