import Foundation
import CoreData
import OSLog

extension DataMigrations {

    /// One-shot backfill: for every `CDLessonAssignment` in `.presented` state, ensure a
    /// `CDLessonPresentation` row exists for each listed student. Historically, four entry
    /// points marked assignments as presented without creating the per-student rows that
    /// mastery / sequence-recap / dashboard views read from; this migration repairs that
    /// divergence for data created before the fix.
    ///
    /// Idempotent: guarded by a `UserDefaults` flag and built on
    /// `LifecycleService.recordPresentation` (which uses `upsertLessonPresentation`).
    @MainActor
    static func backfillLessonPresentationsFromAssignments(using context: NSManagedObjectContext) {
        let key = "DataMigrations.lessonPresentationBackfill.v1.completed"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let logger = Logger.migration

        // CDLessonPresentation is a shared-store entity. In the two-store
        // CloudKit configuration, writing it before a CKShare exists creates
        // orphan records that poison NSCloudKitMirroringDelegate with
        // NSCocoaErrorDomain 134060 for the rest of the session. Defer in
        // that case; the auto-create-on-launch flow + the
        // SharedStoreOrphanGuard save observer will re-invoke this migration.
        // Local-only / in-memory / test stacks have no shared-configured store,
        // so the gate is a no-op there.
        let hasSharedStore = (context.persistentStoreCoordinator?.persistentStores ?? [])
            .contains { $0.configurationName == CoreDataStack.sharedConfiguration }
        if hasSharedStore && !SharedStoreZoneRepair.shared.hasActiveShare {
            logger.info("Backfill: lesson presentations deferred — no active CKShare yet")
            return
        }

        let start = Date()

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "stateRaw == %@",
            LessonAssignmentState.presented.rawValue
        )
        let presented = context.safeFetch(request)

        var processed = 0
        var skipped = 0
        for la in presented {
            guard let presentedAt = la.presentedAt else {
                skipped += 1
                continue
            }
            do {
                _ = try LifecycleService.recordPresentation(
                    from: la,
                    presentedAt: presentedAt,
                    modelContext: context
                )
                processed += 1
            } catch {
                let assignmentID = la.id?.uuidString ?? "nil"
                let errDesc = error.localizedDescription
                logger.warning(
                    "Backfill: recordPresentation failed for assignment \(assignmentID, privacy: .public): \(errDesc)"
                )
            }
        }

        UserDefaults.standard.set(true, forKey: key)
        let elapsed = Date().timeIntervalSince(start)
        let elapsedStr = String(format: "%.2f", elapsed)
        let summary = "processed \(processed), skipped \(skipped) (no presentedAt), in \(elapsedStr)s"
        logger.info("Backfill: lesson presentations — \(summary)")
    }
}
