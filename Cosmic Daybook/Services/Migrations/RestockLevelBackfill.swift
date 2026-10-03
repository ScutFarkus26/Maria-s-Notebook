// RestockLevelBackfill.swift
// Schema 15's one-time launch step: staples kept as counts get a level.

import CoreData
import Foundation
import OSLog

/// Before schema 15 a staple had only a count, and the count stood in for the
/// level: the live shelf read Paper Towels 0, Toilet Paper 0, Air Dry Clay 1.
/// Once (per CloudKit environment), on the lead guide's Mac only (the iPad and
/// iPhone get the levels through sync; `AppBootstrapper` gates the call), every staple whose level was never set gets one from its count: none
/// left is Out, with its open need on the office run; anything else Stocked.
///
/// Judged staple by staple as well as by the flag. Every level write stamps
/// `levelChangedAt` (this step included), and a stamped staple is left alone,
/// so a device that runs this late (one opened days later, a reinstall)
/// leaves the levels set since on another device as they are. It waits out a
/// first download, and runs on the view context so the needs it opens join
/// the classroom share like any other new record (`SharedStoreOrphanGuard`).
///
/// A device that runs it before it has caught up with another's run maps the
/// same staples the same way; `RestockService.reconcile` folds the two needs
/// that makes into one.
nonisolated enum RestockLevelBackfill {
    private static let logger = Logger.migration

    /// The first backup format that carries levels; staples restored from an
    /// older one get theirs from their counts again.
    static let firstFormatWithLevels = 37

    /// Runs once on this device, if it's the lead guide's and the first
    /// download is done. Returns how many staples it set Out; the caller saves.
    @MainActor
    @discardableResult
    static func runIfNeeded(
        in context: NSManagedObjectContext,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> Int {
        let flag = UserDefaultsKeys.restockLevelsFromCounts
        guard !defaults.bool(forKey: flag), !FirstDownloadGate.isPending(defaults: defaults) else { return 0 }
        let role = CDClassroomMembership.currentRole(in: context)
        // An assistant's notebook never decides the classroom's shelf.
        guard role == .leadGuide else { return 0 }
        let out = mapCounts(in: context, by: .current(role: role), at: now)
        defaults.set(true, forKey: flag)
        if out > 0 {
            logger.notice("Restock: \(out, privacy: .public) staple(s) with none left are now Out")
        }
        return out
    }

    /// After a restore: a backup from before levels (format below 37) brings
    /// staples back with counts only, and they get levels from them now. A
    /// newer backup carries the levels and is left as it is. Saves what it
    /// changed and returns how many staples it set Out.
    @MainActor
    @discardableResult
    static func afterRestore(formatVersion: Int, in context: NSManagedObjectContext, now: Date = Date()) -> Int {
        guard formatVersion < firstFormatWithLevels else { return 0 }
        let role = CDClassroomMembership.currentRole(in: context)
        guard role == .leadGuide else { return 0 }
        let out = mapCounts(in: context, by: .current(role: role), at: now)
        if context.hasChanges { context.safeSave() }
        return out
    }

    /// Gives every staple without a level one from its count, stamping each
    /// so it's never judged again. Returns how many it set Out.
    @discardableResult
    static func mapCounts(in context: NSManagedObjectContext, by author: RestockAuthor, at now: Date) -> Int {
        let request = CDFetchRequest(CDSupply.self)
        request.predicate = NSPredicate(format: "levelChangedAt == nil")
        var out = 0
        for supply in context.safeFetch(request) {
            if supply.currentQuantity <= 0 {
                RestockService.setLevel(supply, to: .out, by: author, at: now, in: context)
                out += 1
            }
            // Stocked is the default level; the stamp is what marks it decided.
            if supply.levelChangedAt == nil {
                RestockService.stampLevel(supply, by: author, at: now)
            }
        }
        return out
    }
}
