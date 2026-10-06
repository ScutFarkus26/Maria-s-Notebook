// BackupRestoreGate.swift
// When this device may restore a backup at all.

import CoreData
import Foundation

/// Why a restore can't start on this device right now, in the guide's words.
///
/// - **While the first download from iCloud is under way**
///   (`FirstDownloadGate`): the download keeps filling the store after the
///   restore, so a Replace restore's records would sit beside the copies
///   still arriving (every record twice) and a Merge restore would update
///   records that the download then overwrites.
/// - **When this notebook isn't the lead guide's**: a notebook that joined
///   another guide's classroom as an assistant would write that classroom's
///   records into its own store, where no one shares them.
///
/// The checkpoint a failed restore goes back to is not gated: it puts back
/// what was there.
nonisolated enum BackupRestoreGate {
    /// A restore refused before it began; nothing was changed.
    struct Refusal: ExplainedBackupError {
        let reason: String

        var errorDescription: String? { reason }
    }

    static let stillDownloading = "Your notebook is still downloading from iCloud. "
        + "Restore your backup once the download has finished."
    static let notLeadGuide = "Only the lead guide's notebook can be restored from a backup. "
        + "This notebook joined a classroom as an assistant."

    /// The reason, or nil when a restore may start.
    static func blocker(firstDownloadPending: Bool, role: CDClassroomMembership.ClassroomRole) -> String? {
        if role != .leadGuide { return notLeadGuide }
        if firstDownloadPending { return stillDownloading }
        return nil
    }

    /// The reason for this notebook (`context`'s membership) and device
    /// (`defaults`' first-download flag), or nil when a restore may start.
    static func blocker(in context: NSManagedObjectContext, defaults: UserDefaults = .standard) -> String? {
        blocker(
            firstDownloadPending: FirstDownloadGate.isPending(defaults: defaults),
            role: CDClassroomMembership.currentRole(in: context)
        )
    }
}
