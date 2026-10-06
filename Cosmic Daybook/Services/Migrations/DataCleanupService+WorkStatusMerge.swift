//
//  DataCleanupService+WorkStatusMerge.swift
//  Cosmic Daybook
//
//  Launch-time fold of the retired completion outcome into `WorkStatus`
//  (2026-09-15). Deliberately not flag-gated: a device that has not updated
//  yet, an initial CloudKit sync still arriving, or a restored backup can
//  deliver a `complete` + outcome row long after a first pass ran, and the
//  read matches nothing on a store that is already merged.
//
//  Since 2026-10-05 the outcome is cleared once folded, and wherever an
//  earlier build left it. Left in place, it folded again: a row folded to
//  Mastered, reopened and closed as plain Done read as `complete` +
//  `proficient` once more, and the next launch made it Mastered on every
//  device. The folded status is the record of what was there.
//

import CoreData
import Foundation
import OSLog

nonisolated extension DataCleanupService {

    /// Rewrites `statusRaw` on every row that still carries the old
    /// `complete` + outcome pair, per `WorkStatusMigration.merged`, and clears
    /// `completionOutcomeRaw` on every row that has one. Returns how many rows
    /// changed. Never saves.
    @discardableResult
    static func mergeWorkCompletionOutcomes(using context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "completionOutcomeRaw != nil")
        var changed = 0
        for work in context.safeFetch(request) where !work.isDeleted {
            let merged = WorkStatusMigration.merged(statusRaw: work.statusRaw, outcomeRaw: work.completionOutcomeRaw)
            if merged != work.statusRaw {
                work.statusRaw = merged
            }
            work.completionOutcomeRaw = nil
            changed += 1
        }
        if changed > 0 {
            logger.info("Work status merge: folded and cleared \(changed, privacy: .public) retired outcome(s)")
        }
        return changed
    }
}
