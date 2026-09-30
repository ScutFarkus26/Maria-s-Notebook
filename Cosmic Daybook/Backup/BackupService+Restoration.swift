import Foundation
import CoreData
import SwiftUI
import OSLog

// MARK: - Restore Errors

/// Error thrown when a `.replace` restore cannot fully clear existing data.
/// It propagates through `BackupTransactionManager.executeWithRollback`, which
/// rolls back to the safety checkpoint — returning the user to their pre-restore
/// state instead of leaving a half-cleared store.
private enum RestoreClearError: LocalizedError {
    case replaceClearIncomplete([String])

    var errorDescription: String? {
        switch self {
        case .replaceClearIncomplete(let names):
            return "Restore was stopped because existing \(names.joined(separator: ", ")) "
                + "could not be cleared. Your data was returned to its previous state \u{2014} please try again."
        }
    }
}

/// Error thrown when edits the view context held before a restore began
/// cannot be saved first (see `saveEditsMadeBeforeRestore`). Nothing has been
/// restored, and those edits are left unsaved, as they were.
private enum RestoreStartError: LocalizedError {
    case unsavedEditsNotSaved(reason: String)

    var errorDescription: String? {
        switch self {
        case .unsavedEditsNotSaved(let reason):
            return "The restore didn't start because changes that weren't saved yet "
                + "couldn't be saved first: \(reason)"
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

        let run = try discardingChangesOnFailure(in: viewContext) {
            try importEverything(from: source, into: viewContext, mode: mode, appRouter: appRouter, progress: progress)
        }

        // Subscribe to CloudKit export events BEFORE saving — a fast export
        // could otherwise complete between save() and subscription, leaving
        // the user staring at a 30-second timeout for an event that already
        // fired.
        let cloudExportWait = Task {
            await awaitCloudKitExport(viewContext: viewContext, timeout: .seconds(30))
        }
        defer { cloudExportWait.cancel() }

        try discardingChangesOnFailure(in: viewContext) {
            progress(RestoreProgress.saving, "Saving\u{2026}")
            try viewContext.save()

            progress(RestoreProgress.denormalizedRepair, "Repairing denormalized fields\u{2026}")
            try repairDenormalizedFields(viewContext: viewContext)
        }

        applyPreferencesDTO(source.preferences)
        AttendanceDayLocks.carryOverRestoredLocks(
            source.preferences, formatVersion: source.envelope.formatVersion, into: viewContext
        )
        AlbumLibrary.shared.reloadAfterRestore()
        appRouter.signalAppDataDidRestore()

        // After save, the in-memory model is correct but CloudKit-mirrored stores still need
        // to upload the new records. Block briefly so users see a definitive "synced" message
        // when possible; on timeout, surface that sync is continuing in the background.
        progress(RestoreProgress.cloudSync, "Syncing to iCloud\u{2026}")
        let cloudResult = await cloudExportWait.value
        let warnings = restoreWarnings(albumIDs: run.albumIDs, cloudResult: cloudResult)

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
                // types couldn't be cleared, abort so the transaction manager rolls
                // back to the safety checkpoint instead of importing on top of a
                // half-cleared store. The checkpoint is guaranteed for .replace, so
                // the user is returned to their pre-restore state.
                throw RestoreClearError.replaceClearIncomplete(failedEntities)
            }
        }

        // One fetch per entity type instead of one fetch per record. Built
        // lazily so child-type lookups see parents inserted earlier in this
        // same restore (see BackupEntityIndex).
        let run = BackupRestoreRun(source: source, context: viewContext)
        try importEveryType(run, progress: progress)

        // Notes import early, but many of their relationship targets (work,
        // check-ins, meetings, etc.) import in later phases — relink them now
        // that every target type is in the store.
        try BackupEntityImporter.relinkNoteRelationships(run.noteLinks, index: run.index)
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
    }

    /// The restore's own warnings for the summary: the album reattach warning,
    /// then how the post-restore CloudKit export went.
    private func restoreWarnings(albumIDs: Set<String>, cloudResult: CloudExportWaitResult) -> [String] {
        var warnings: [String] = []
        if let albumWarning = albumReattachWarning(for: albumIDs) {
            warnings.append(albumWarning)
        }
        switch cloudResult {
        case .completed:
            break
        case .failed(let reason):
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

    // MARK: - Album Reattachment

    /// Album bookmarks, notes, highlights, and ink key on the album PDF's
    /// filename. They restore intact, but on a device with no album folder
    /// registered they have nothing to attach to until the guide adds one —
    /// say so, rather than letting them look lost. `albumIDs` holds every
    /// album the restored bookmarks, page notes, highlights, ink and reading
    /// positions name (`BackupRestoreRun.albumIDs`).
    private func albumReattachWarning(for albumIDs: Set<String>) -> String? {
        guard !albumIDs.isEmpty, !AlbumLibrary.hasResolvableFolderBookmark() else { return nil }
        let noun = albumIDs.count == 1 ? "album" : "albums"
        return "This backup includes bookmarks, notes, highlights, or drawings for "
            + "\(albumIDs.count) \(noun). Open Albums and add your album folder to reattach them."
    }

    // MARK: - CloudKit Export Wait

    /// Waits for an `NSPersistentCloudKitContainer` `.export` event to complete after a restore.
    /// Returns immediately if no CloudKit-backed store is attached (e.g., test in-memory stack).
    private func awaitCloudKitExport(
        viewContext: NSManagedObjectContext,
        timeout: Duration
    ) async -> CloudExportWaitResult {
        // Skip the wait when there's no CloudKit-mirrored store (in-memory tests, local-only fallback).
        guard isCloudKitMirrored(viewContext: viewContext) else { return .completed }

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

    /// True when `viewContext` is attached to at least one CloudKit-mirrored persistent store.
    /// Detects the in-memory test stack and skips the export wait.
    private func isCloudKitMirrored(viewContext: NSManagedObjectContext) -> Bool {
        guard let stores = viewContext.persistentStoreCoordinator?.persistentStores else { return false }
        for store in stores {
            if store.type == NSInMemoryStoreType { continue }
            // Any non-memory SQLite store in this app is CloudKit-mirrored by configuration.
            if store.type == NSSQLiteStoreType { return true }
        }
        return false
    }

    // MARK: - Denormalized Fields

    private func repairDenormalizedFields(viewContext: NSManagedObjectContext) throws {
        let assignmentsForRepair = try viewContext.fetch(
            CDFetchRequest(CDLessonAssignment.self)
        )
        var repairedCount = 0
        for la in assignmentsForRepair {
            let correct = la.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
            if la.scheduledForDay != correct {
                la.scheduledForDay = correct
                repairedCount += 1
            }
        }
        if repairedCount > 0 {
            try viewContext.save()
        }
    }
}
