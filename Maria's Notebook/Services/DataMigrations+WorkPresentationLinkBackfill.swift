import Foundation
import CoreData
import OSLog

extension DataMigrations {

    /// One-shot backfill: link `CDWorkModel` rows created before the presentationID fix
    /// to the lesson assignment they belong to. `createWork` historically wrote the
    /// resolved assignment ID only into the legacy `studentLessonID` field, leaving
    /// `presentationID` nil for every work item the main presentation workflow created.
    /// Readiness, blocking, and mastery checks all key work on `presentationID`, so an
    /// unlinked practice item could never satisfy a required-practice gate and the
    /// student never became ready for the next lesson.
    ///
    /// Uses the same assignment preference as `WorkRepository.preferredAssignment`,
    /// so backfilled links match what `createWork` produces today. Both stores hold
    /// only private-store entities here (WorkModel writes, LessonAssignment reads),
    /// so no CKShare gate is needed. Every device resolves the same deterministic
    /// link, so concurrent one-shot runs on synced devices converge.
    ///
    /// Idempotent: guarded by a `UserDefaults` flag and only touches unlinked rows.
    /// Runs on the view context; the bootstrapper batches the save.
    @MainActor
    static func backfillWorkPresentationLinks(using context: NSManagedObjectContext) {
        let key = "DataMigrations.workPresentationLinkBackfill.v1.completed"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let logger = Logger.migration
        let start = Date()

        let workRequest = CDFetchRequest(CDWorkModel.self)
        workRequest.predicate = NSPredicate(format: "presentationID == nil OR presentationID == %@", "")
        let unlinked = context.safeFetch(workRequest)

        guard !unlinked.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            logger.info("Backfill: work presentation links — nothing to link")
            return
        }

        // One assignment fetch grouped by lesson, instead of a fetch per work item.
        let assignments = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        let assignmentsByLessonID = Dictionary(grouping: assignments, by: \.lessonID)

        var linked = 0
        var skipped = 0
        for work in unlinked {
            // Group work may carry its students only as participants, so match the
            // assignment against every student the work names.
            var workStudentIDs = Set(
                (work.participants?.allObjects as? [CDWorkParticipantEntity])?.map(\.studentID) ?? []
            )
            if !work.studentID.isEmpty { workStudentIDs.insert(work.studentID) }

            let candidates = (assignmentsByLessonID[work.lessonID] ?? []).filter { la in
                workStudentIDs.contains { la.studentIDs.contains($0) }
            }
            guard let assignmentID = WorkRepository.preferredAssignment(among: candidates)?.id else {
                skipped += 1
                continue
            }
            work.presentationID = assignmentID.uuidString
            if work.studentLessonID == nil {
                work.studentLessonID = assignmentID
            }
            linked += 1
        }

        UserDefaults.standard.set(true, forKey: key)
        let elapsedStr = String(format: "%.2f", Date().timeIntervalSince(start))
        let summary = "linked \(linked), no matching assignment for \(skipped), in \(elapsedStr)s"
        logger.info("Backfill: work presentation links — \(summary)")
    }
}
