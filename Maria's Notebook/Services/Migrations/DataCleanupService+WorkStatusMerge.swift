//
//  DataCleanupService+WorkStatusMerge.swift
//  Maria's Notebook
//
//  Launch-time fold of the retired completion outcome into `WorkStatus`
//  (2026-09-15). Deliberately not flag-gated: a device that has not updated
//  yet, or an initial CloudKit sync still arriving, can deliver a
//  `complete` + outcome row long after a first pass ran, and the indexed
//  predicate matches nothing on a store that is already merged.
//

import CoreData
import Foundation
import OSLog

nonisolated extension DataCleanupService {

    /// Rewrites `statusRaw` on every row that still carries the old
    /// `complete` + outcome pair, per `WorkStatusMigration.merged`. Leaves
    /// `completionOutcomeRaw` in place — it is the record of what was there.
    /// Returns how many rows changed. Never saves.
    @discardableResult
    static func mergeWorkCompletionOutcomes(using context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "statusRaw == %@ AND completionOutcomeRaw != nil", WorkStatus.done.rawValue
        )
        var changed = 0
        for work in context.safeFetch(request) where !work.isDeleted {
            let merged = WorkStatusMigration.merged(statusRaw: work.statusRaw, outcomeRaw: work.completionOutcomeRaw)
            guard merged != work.statusRaw else { continue }
            work.statusRaw = merged
            changed += 1
        }
        if changed > 0 {
            logger.info("Work status merge: folded \(changed, privacy: .public) outcome(s) into status")
        }
        return changed
    }
}
