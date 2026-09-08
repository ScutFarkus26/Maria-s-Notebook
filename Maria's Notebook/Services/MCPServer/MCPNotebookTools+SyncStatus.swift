//
//  MCPNotebookTools+SyncStatus.swift
//  Maria's Notebook
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
            description: "Whether the notebook is syncing to iCloud: overall health, the last "
                + "successful sync, how many local changes are still waiting, and any error. "
                + "Use this when the guide asks whether their data is safe or why a device "
                + "looks out of date.",
            inputSchema: ["type": "object", "properties": [:]],
            handler: { _ in
                describeSyncStatus()
            }
        )
    }

    private static func describeSyncStatus() -> String {
        let service = CloudKitSyncStatusService.shared
        var lines: [String] = ["Sync: \(healthLabel(service.syncHealth))"]

        if let last = service.lastSuccessfulSync {
            lines.append("  Last successful sync: \(dayString(last)) at \(timeString(last))")
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
        if let error = nonEmpty(service.lastSyncError) {
            lines.append("  Last error: \(error)")
        }
        // A failed mirroring delegate is terminal for the process: nothing will
        // sync again until the app restarts, so it must not be buried.
        if service.mirroringDelegateFailed {
            lines.append(
                "  WARNING: CloudKit's mirroring delegate failed to start this session. "
                    + "Nothing will sync until the app is restarted."
            )
        }
        return lines.joined(separator: "\n")
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
