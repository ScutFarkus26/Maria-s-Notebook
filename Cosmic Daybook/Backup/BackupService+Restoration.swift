import Foundation
import CoreData
import SwiftUI
import OSLog

// MARK: - Restore Errors

/// Error thrown when a `.replace` restore cannot fully clear existing data.
/// Nothing is saved by then (the clear is saved with the import), so the
/// restore's own changes are discarded and the notebook is as it was.
nonisolated private enum RestoreClearError: ExplainedBackupError {
    case replaceClearIncomplete([String])

    /// The types that wouldn't clear ride along for the log (`executeWithRollback` logs it).
    var errorDescription: String? {
        switch self {
        case .replaceClearIncomplete:
            return "The restore stopped because some of your current notebook couldn't be cleared first. "
                + "Your notebook was put back the way it was. Try again."
        }
    }
}

/// Error thrown when edits the view context held before a restore began
/// cannot be saved first (see `saveEditsMadeBeforeRestore`). Nothing has been
/// restored, and those edits are left unsaved, as they were.
nonisolated private enum RestoreStartError: ExplainedBackupError {
    case unsavedEditsNotSaved(reason: String)

    /// The save's own error rides along in `reason` for the log (`executeWithRollback` logs it).
    var errorDescription: String? {
        switch self {
        case .unsavedEditsNotSaved:
            return "The restore didn't start because your latest changes couldn't be saved first. "
                + "Nothing was changed. Try again."
        }
    }
}

// MARK: - Import Progress Steps

/// Named progress milestones for backup restoration, replacing inline magic numbers.
/// Each value corresponds to the fraction-complete reported to the caller's ProgressCallback.
private enum RestoreProgress {
    static let deduplication: Double = 0.35
    static let clearing: Double = 0.40
    static let coreEntities: Double = 0.65
    static let workTracking: Double = 0.70
    static let lessonExtras: Double = 0.74
    static let templates: Double = 0.76
    static let tracks: Double = 0.78
    static let documentsSupplies: Double = 0.80
    static let schedules: Double = 0.82
    static let issues: Double = 0.84
    static let snapshotsTodos: Double = 0.86
    static let additionalEntities: Double = 0.88
    static let saving: Double = 0.90
    static let denormalizedRepair: Double = 0.92
    static let cloudSync: Double = 0.96
    static let done: Double = 1.00
}

/// Outcome of waiting for `NSPersistentCloudKitContainer` to finish the post-restore export.
enum CloudExportWaitResult: Sendable {
    /// No CloudKit-backed store, or the wait completed and a `.export` event succeeded.
    case completed
    /// `.export` event arrived but reported `succeeded == false`. Carries a localized description
    /// (not the underlying `Error` — `any Error` doesn't cross task boundaries cleanly).
    case failed(reason: String?)
    /// Timed out before any complete `.export` event arrived. Sync is still running in the background.
    case timedOut
}

// MARK: - Restore

extension BackupService {
    /// Restores a whole decoded payload: how tests that build a payload by
    /// hand restore. The app restores archives through
    /// `BackupImporter.restore`; both go through `importRows`.
    func importPayload(
        payload loadedPayload: BackupPayload,
        envelope: BackupEnvelope,
        viewContext: NSManagedObjectContext,
        mode: RestoreMode,
        appRouter: AppRouter,
        progress: @escaping ProgressCallback
    ) async throws -> BackupOperationSummary {
        try await importRows(
            from: BackupPayloadSource(loadedPayload, envelope: envelope),
            viewContext: viewContext,
            mode: mode,
            appRouter: appRouter,
            progress: progress
        )
    }

    /// The restore, for every path: the app's archive restore
    /// (`BackupImporter.restore`), the checkpoint rollback, and
    /// `importPayload`. Centralizing it means deleteAll, the entity-import
    /// dispatch, the denormalized-field repair, and the CloudKit-sync wait all
    /// share one code path across format versions.
    ///
    /// Types are imported in dependency order through `BackupRestoreRun`, each
    /// taken from `source` when its turn comes and freed once imported.
    /// Everything from the replace-mode clear to `viewContext.save()` runs in
    /// one main-actor turn — nothing in it suspends. Keep it that way: between
    /// types, the quit-time backup would export a half-restored store and let
    /// the app quit before the save (after replace mode's clear has already
    /// been saved), a scheduled or background backup would write one, an MCP
    /// write could save or roll back the restore's pending changes, and
    /// `isRestoring` would swap Settings — with this restore's progress and
    /// summary — out of the window.
    ///
    /// Edits the view context already held are saved first, and a failure
    /// before the restore's own save completes discards everything it left
    /// unsaved: in that one turn, nothing else can have changed the context,
    /// so a failed restore leaves neither half a restore for the next save
    /// anywhere to commit nor any loss of the guide's own edits.
    func importRows(
        from source: any BackupRestoreSource,
        viewContext: NSManagedObjectContext,
        mode: RestoreMode,
        appRouter: AppRouter,
        progress: @escaping ProgressCallback
    ) async throws -> BackupOperationSummary {
        // Each type is deduplicated as `source` hands it over; the line keeps
        // its place so the guide sees the same progress.
        progress(RestoreProgress.deduplication, "Deduplicating records\u{2026}")
        try saveEditsMadeBeforeRestore(in: viewContext)

        let run: BackupRestoreRun
        do {
            run = try discardingChangesOnFailure(in: viewContext) {
                try importEverything(
                    from: source, into: viewContext, mode: mode, appRouter: appRouter, progress: progress
                )
            }
        } catch {
            endUnsavedReplace(mode, appRouter: appRouter)
            throw error
        }

        // Subscribe to CloudKit export events BEFORE saving — a fast export
        // could otherwise complete between save() and subscription, leaving
        // the user staring at a 30-second timeout for an event that already
        // fired.
        let cloudExportWait = Task {
            await awaitCloudKitExport(viewContext: viewContext, timeout: .seconds(30))
        }
        defer { cloudExportWait.cancel() }

        do {
            try saveRestore(in: viewContext, progress: progress)
        } catch let error as BackupRestoreSavedError {
            // Saved: the checkpoint's rollback follows, and it signals on its own.
            throw error
        } catch {
            endUnsavedReplace(mode, appRouter: appRouter)
            throw error
        }

        applyPreferencesDTO(source.preferences)
        AttendanceDayLocks.carryOverRestoredLocks(
            source.preferences, formatVersion: source.envelope.formatVersion, into: viewContext
        )
        // A backup from before Restock's levels (v36 and older) brings staples
        // back with counts only; they get levels from them, as at launch.
        RestockLevelBackfill.afterRestore(formatVersion: source.envelope.formatVersion, in: viewContext)
        AlbumLibrary.shared.reloadAfterRestore()
        appRouter.signalAppDataDidRestore()

        // After save, the in-memory model is correct but CloudKit-mirrored stores still need
        // to upload the new records. Block briefly so users see a definitive "synced" message
        // when possible; on timeout, surface that sync is continuing in the background.
        progress(RestoreProgress.cloudSync, "Syncing to iCloud\u{2026}")
        let cloudResult = await cloudExportWait.value
        let warnings = restoreWarnings(
            albumIDs: run.albumIDs, notesMissingTheirReminder: run.notesMissingTheirReminder, cloudResult: cloudResult
        )

        progress(RestoreProgress.done, "Done")
        let envelope = source.envelope
        return BackupOperationSummary(
            kind: .import,
            fileName: envelope.fileName,
            formatVersion: envelope.formatVersion,
            encryptUsed: envelope.encrypted,
            createdAt: envelope.createdAt,
            entityCounts: envelope.entityCounts,
            warnings: warnings
        )
    }

    /// The restore's one save and the repair after it. A failure before the
    /// save completes throws the save's own error, with every unsaved change
    /// discarded; one after it throws `BackupRestoreSavedError`.
    private func saveRestore(in viewContext: NSManagedObjectContext, progress: ProgressCallback) throws {
        try discardingChangesOnFailure(in: viewContext) {
            progress(RestoreProgress.saving, "Saving\u{2026}")
            BackupRestoreScope.assignInsertsToPrivateStore(in: viewContext)
            // The restore's one save: replace mode's clear and every record
            // together. Until it succeeds the store holds none of the restore.
            try viewContext.save()

            do {
                try BackupPipelineProbe.reachOrFail("saved")
                progress(RestoreProgress.denormalizedRepair, "Repairing denormalized fields\u{2026}")
                try repairDenormalizedFields(viewContext: viewContext)
            } catch {
                throw BackupRestoreSavedError(underlying: error)
            }
        }
    }

    /// A Replace that stops before its save leaves the notebook as it was, but
    /// the screens were told it was being replaced
    /// (`signalAppDataWillBeReplaced`): tell them it's over, or they wait on
    /// "Restoring your backup…" until the app is relaunched (2026-10-05
    /// review). A failure after the save goes on to the checkpoint's rollback,
    /// which signals on its own.
    private func endUnsavedReplace(_ mode: RestoreMode, appRouter: AppRouter) {
        guard mode == .replace else { return }
        appRouter.signalAppDataDidRestore()
    }

    /// Saves edits the view context held before this restore began. The
    /// restore's own save would commit them anyway, as it always has; saving
    /// them first is what lets a failure discard exactly the restore's changes
    /// and none of these. If they can't be saved, the restore doesn't begin
    /// and they stay unsaved.
    private func saveEditsMadeBeforeRestore(in viewContext: NSManagedObjectContext) throws {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            throw RestoreStartError.unsavedEditsNotSaved(reason: error.localizedDescription)
        }
    }

    /// `body`, and if it throws, every unsaved change in `viewContext`
    /// discarded first — by then only the restore's own (see `importRows`).
    private func discardingChangesOnFailure<T>(
        in viewContext: NSManagedObjectContext,
        _ body: () throws -> T
    ) throws -> T {
        do {
            return try body()
        } catch {
            viewContext.rollback()
            throw error
        }
    }

    /// Everything the restore changes before its save: the replace-mode clear,
    /// every type imported, then notes relinked.
    private func importEverything(
        from source: any BackupRestoreSource,
        into viewContext: NSManagedObjectContext,
        mode: RestoreMode,
        appRouter: AppRouter,
        progress: ProgressCallback
    ) throws -> BackupRestoreRun {
        if mode == .replace {
            progress(RestoreProgress.clearing, "Clearing existing data\u{2026}")
            appRouter.signalAppDataWillBeReplaced()
            let failedEntities = try deleteAll(viewContext: viewContext)
            if !failedEntities.isEmpty {
                // Replace mode must fully clear the store before importing. If some
                // types couldn't be cleared, abort rather than import on top of a
                // half-cleared store; the clear isn't saved, so it is discarded
                // with the rest and the notebook stays as it was.
                throw RestoreClearError.replaceClearIncomplete(failedEntities)
            }
        }

        // One fetch per entity type instead of one fetch per record. Built
        // lazily so child-type lookups see parents inserted earlier in this
        // same restore (see BackupEntityIndex).
        let run = BackupRestoreRun(source: source, context: viewContext)
        try importEveryType(run, progress: progress)
        // An older backup's rows lack attributes added since; the records it
        // updated keep their own values for those.
        run.index.predatedValues.putBack()

        // Notes import early, but many of their relationship targets (work,
        // check-ins, meetings, etc.) import in later phases — relink them now
        // that every target type is in the store.
        run.notesMissingTheirReminder = try BackupEntityImporter.relinkNoteRelationships(
            run.noteLinks, index: run.index
        )
        try run.matchStudentLinksToScope()
        return run
    }

    /// Every backed-up type, in the order the restore imports it: parents
    /// before the types that link to them. The archive's order differs
    /// (`BackupEntityTable`), so the source hands each type over when its
    /// turn comes, whatever order the archive holds them in.
    private func importEveryType(_ run: BackupRestoreRun, progress: ProgressCallback) throws {
        progress(RestoreProgress.coreEntities, "Importing records\u{2026}")
        try run.importCoreEntities()
        try run.importCalendarAndRecordEntities()
        try run.importProjectEntities()

        progress(RestoreProgress.workTracking, "Importing work tracking\u{2026}")
        try run.importWorkTrackingEntities()

        progress(RestoreProgress.lessonExtras, "Importing lesson extras\u{2026}")
        try run.importLessonExtras()

        progress(RestoreProgress.templates, "Importing templates\u{2026}")
        try run.importTemplateEntities()

        progress(RestoreProgress.tracks, "Importing tracks\u{2026}")
        try run.importTrackEntities()

        progress(RestoreProgress.documentsSupplies, "Importing documents & supplies\u{2026}")
        try run.importDocumentEntities()

        progress(RestoreProgress.schedules, "Importing schedules\u{2026}")
        try run.importScheduleEntities()

        progress(RestoreProgress.issues, "Importing issues\u{2026}")
        try run.importIssueEntities()

        progress(RestoreProgress.snapshotsTodos, "Importing snapshots & todos\u{2026}")
        try run.importSnapshotAndTodoEntities()

        progress(RestoreProgress.additionalEntities, "Importing recommendations, resources & links\u{2026}")
        try run.importAdditionalEntities()
        try run.importV12Entities()
        try run.importV13AndV14Entities()
        try run.importV18Entities()
        try run.importV20Entities()
        try run.importV21Entities()
        try run.importV27Entities()
        try run.importV30Entities()
        try run.importV31Entities()
        try run.importV34Entities()
        try run.importV38Entities()
    }

    /// The restore's own warnings for the summary: the album reattach warning,
    /// notes whose reminder isn't on this device, then how the post-restore
    /// CloudKit export went.
    private func restoreWarnings(
        albumIDs: Set<String>, notesMissingTheirReminder: Int, cloudResult: CloudExportWaitResult
    ) -> [String] {
        var warnings: [String] = []
        if let albumWarning = albumReattachWarning(for: albumIDs) {
            warnings.append(albumWarning)
        }
        if notesMissingTheirReminder > 0 {
            warnings.append(BackupWarningText.notesMissingTheirReminder(notesMissingTheirReminder))
        }
        switch cloudResult {
        case .completed:
            break
        case .failed(let reason):
            // Raw for Details; `BackupWarningText.plain` words it for the screen.
            let detail = reason ?? "unknown error"
            warnings.append(
                "iCloud sync reported a failure: \(detail). " +
                "Your data is saved locally; check Settings → iCloud to retry."
            )
        case .timedOut:
            warnings.append(
                "iCloud sync is still running in the background. " +
                "Keep the app open for a moment to finish uploading."
            )
        }
        return warnings
    }

    // MARK: - CloudKit Export Wait

    /// Waits for an `NSPersistentCloudKitContainer` `.export` event to complete after a restore.
    /// Returns at once when the restore went into a notebook that doesn't sync (see the guard).
    private func awaitCloudKitExport(
        viewContext: NSManagedObjectContext,
        timeout: Duration
    ) async -> CloudExportWaitResult {
        // Skip the wait unless the restore went into the app's notebook while it
        // syncs: in-memory tests, iCloud sync off, the local-only fallback and
        // the database-error screen's fresh notebook (`FreshNotebookRestore`)
        // never export, and would only wait 30 seconds to say sync is "still
        // running in the background".
        guard BackupRestoreScope.syncsWithICloud(viewContext) else { return .completed }

        let events = NotificationCenter.default.messages(
            of: NSPersistentCloudKitContainer.self, for: .eventChanged, bufferSize: 256
        )

        return await withTaskGroup(of: CloudExportWaitResult.self) { group in
            group.addTask {
                for await message in events {
                    let event = message.event
                    guard event.type == .export, event.endDate != nil else { continue }
                    if event.succeeded {
                        return .completed
                    } else {
                        return .failed(reason: event.error?.localizedDescription)
                    }
                }
                return .timedOut
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }
}
