import Foundation
import CoreData
import OSLog

// MARK: - Data Migrations Facade

/// Central facade for data migrations.
/// Delegates to DataCleanupService for ongoing cleanup and deduplication.
nonisolated enum DataMigrations {
    // MARK: - Data Cleanup (delegated to DataCleanupService)

    /// Remove all duplicate records across all model types.
    /// Pass the CloudKit container when available so survivor selection is
    /// deterministic across devices (falls back to the CloudKit record name).
    @discardableResult
    static func deduplicateAllModels(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil
    ) -> [String: Int] {
        DataCleanupService.deduplicateAllModels(using: context, container: container)
    }

    /// Repairs the `scheduledForDay` mirror. Does not touch `scheduledFor`,
    /// which carries each lesson's position within its day.
    ///
    /// No longer part of the launch pass (2026-10-05): nothing fetches by the
    /// mirror, schedule writes keep it, and rewriting it on every device made
    /// synced writes for nothing. On `context`'s queue.
    static func repairScheduledForDayMirror(using context: NSManagedObjectContext) {
        DataCleanupService.repairScheduledForDayMirror(using: context)
    }

    /// Cleans orphaned student IDs from CDLessonAssignment records.
    /// On `context`'s queue (the launch pass: a background context's `perform`).
    static func cleanOrphanedStudentIDs(using context: NSManagedObjectContext, grace: OrphanStudentGrace? = nil) {
        DataCleanupService.cleanOrphanedStudentIDs(using: context, grace: grace)
    }

    /// Cleans orphaned student IDs from CDWorkModel records; returns how many rows changed.
    /// On `context`'s queue (the launch pass: a background context's `perform`).
    @discardableResult
    static func cleanOrphanedWorkStudentIDs(
        using context: NSManagedObjectContext, grace: OrphanStudentGrace? = nil
    ) -> Int {
        DataCleanupService.cleanOrphanedWorkStudentIDs(using: context, grace: grace)
    }

    /// Clean up orphaned note images that are no longer referenced by any CDNote.
    static func cleanupOrphanedNoteImages(using context: NSManagedObjectContext) {
        DataCleanupService.cleanupOrphanedNoteImages(using: context)
    }

    /// Relink check-ins that carry only a `workID` string, and drop the ones
    /// whose work is gone.
    ///
    /// An orphan goes only when all of these hold: the repair has run (and
    /// saved) on this device before (`markCheckInLinkRepairRun`), the first
    /// download is done (`FirstDownloadGate`), and its work has been missing
    /// on passes a day apart with an import into the private store since it
    /// was first seen missing (`OrphanStudentGrace`, kind `.checkInWork`,
    /// whose ledger lives in `defaults`). `lastImport` says when a store last
    /// finished an import; with none known, orphans keep waiting. While the
    /// first download runs nothing is judged or recorded. Never saves, and
    /// never sets the "has run" flag itself.
    @discardableResult
    static func repairWorkCheckInLinks(
        using context: NSManagedObjectContext,
        firstDownloadPending: Bool = FirstDownloadGate.isPending(),
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        lastImport: (ImportStoreKind) -> Date? = { _ in nil }
    ) -> DataCleanupService.CheckInRepairReport {
        guard !firstDownloadPending else {
            return DataCleanupService.repairWorkCheckInLinks(using: context, deleteOrphans: false)
        }
        let hasRunBefore = defaults.bool(forKey: UserDefaultsKeys.checkInLinkRepairHasRun)
        // Work rows live in the private store on every device.
        let grace = OrphanStudentGrace(
            ledger: OrphanStudentGrace.load(from: defaults, kind: .checkInWork),
            now: now,
            lastImport: lastImport(.privateStore)
        )
        let report = DataCleanupService.repairWorkCheckInLinks(
            using: context, deleteOrphans: hasRunBefore, grace: grace
        )
        OrphanStudentGrace.save(grace.ledger, to: defaults, kind: .checkInWork)
        return report
    }

    /// Counts the check-in repair's first run on this device, once the pass
    /// that ran it has saved. A run during the first download doesn't count.
    static func markCheckInLinkRepairRun(firstDownloadPending: Bool, defaults: UserDefaults = .standard) {
        guard !firstDownloadPending else { return }
        defaults.set(true, forKey: UserDefaultsKeys.checkInLinkRepairHasRun)
    }

    /// Whether the one-time note scope index repair should run in this pass:
    /// not yet done on this device, and not during the first download.
    static func noteScopeIndexRepairDue(firstDownloadPending: Bool, defaults: UserDefaults = .standard) -> Bool {
        !firstDownloadPending && !defaults.bool(forKey: UserDefaultsKeys.noteScopeIndexRepairDone)
    }

    /// Notes saved with no scope blob join the whole-class search index (see
    /// +NoteScopeIndex). Never saves; the caller marks it done after its save.
    @discardableResult
    static func repairMissingNoteScopeIndex(using context: NSManagedObjectContext) -> Int {
        DataCleanupService.repairMissingNoteScopeIndex(using: context)
    }

    /// Counts the note scope index repair as done, once the pass that ran it has saved.
    static func markNoteScopeIndexRepairDone(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: UserDefaultsKeys.noteScopeIndexRepairDone)
    }

    /// Narrow whole-class notes written on a presentation to its roster.
    @discardableResult
    static func repairPresentationNoteScopes(using context: NSManagedObjectContext) -> Int {
        DataCleanupService.repairPresentationNoteScopes(using: context)
    }

    /// Fold the retired `completionOutcomeRaw` into `statusRaw` on rows that
    /// still carry the pair, and clear it wherever it is left. Cheap and
    /// idempotent, so it runs every launch.
    @discardableResult
    static func mergeWorkCompletionOutcomes(using context: NSManagedObjectContext) -> Int {
        DataCleanupService.mergeWorkCompletionOutcomes(using: context)
    }
}
