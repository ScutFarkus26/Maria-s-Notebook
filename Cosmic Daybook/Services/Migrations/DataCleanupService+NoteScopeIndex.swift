import Foundation
import CoreData
import os

// MARK: - Note Scope Index Repair

nonisolated extension DataCleanupService {

    /// Notes saved with no scope blob read as `.all` (`CDNote.scope`), but
    /// until 2026-10-05 the initializer left their search index unset
    /// (`scopeIsAll == NO`, no student), which is how a note for several
    /// students looks, so the queries that find whole-class notes by
    /// `scopeIsAll == YES` (a child's notes tab, her notes list) missed them.
    /// This sets `scopeIsAll` on exactly those notes, so the index agrees with what the
    /// note reads as. A nil-blob note that names a student
    /// (`searchIndexStudentID`) or has student links is left alone: those
    /// already say who it is for.
    ///
    /// Writes only rows that differ, and never the blob, so it changes as
    /// little as it can and a second run finds nothing. Meant to run once
    /// (the caller keeps the flag, sets it only after its save succeeds, and
    /// skips it while `FirstDownloadGate.isPending()`). Synchronous, on
    /// `context`'s queue; it doesn't save. Returns how many notes it changed.
    @discardableResult
    static func repairMissingNoteScopeIndex(using context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "scopeBlob == nil AND scopeIsAll == NO AND searchIndexStudentID == nil "
                + "AND studentLinks.@count == 0"
        )
        var changed = 0
        for note in context.safeFetch(request) where !note.isDeleted && note.scopeBlob == nil {
            note.scopeIsAll = true
            changed += 1
        }
        if changed > 0 {
            logger.info("Marked \(changed, privacy: .public) unscoped note(s) as whole-class in the search index")
        }
        return changed
    }

    // MARK: - Multi-Child Note Links

    /// Notes about several children (`.students` scope) are found on each
    /// child's Notes tab only through their `NoteStudentLink`s. Until
    /// 2026-10-10 Quick Note and the note editor never made them, re-scoping a
    /// note in the editor left the old ones, and a group check-in's note had
    /// none, so such notes showed on none of the children's tabs, or on a tab
    /// they no longer named. This gives each multi-child note exactly the links
    /// its scope names, through the same diff every note writer uses
    /// (`CDNote.syncStudentLinks`): only a missing child gets a link, only a
    /// link for a child the scope doesn't name goes, and a note already right
    /// isn't written. It adds no facts: the scope is what the guide chose.
    ///
    /// Other scopes are left alone (Danny's answer, 2026-10-10: only the
    /// clear-cut case). Synchronous, on `context`'s queue; it doesn't save.
    /// Returns how many notes it changed.
    @discardableResult
    static func repairNoteStudentLinks(using context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "scopeBlob != nil AND scopeIsAll == NO AND searchIndexStudentID == nil"
        )
        request.relationshipKeyPathsForPrefetching = ["studentLinks"]
        var changed = 0
        for note in context.safeFetch(request) where !note.isDeleted {
            guard case .students = note.scope else { continue }
            if note.syncStudentLinks(in: context) { changed += 1 }
        }
        if changed > 0 {
            logger.info("Matched the student links of \(changed, privacy: .public) multi-child note(s) to their scope")
        }
        return changed
    }

    /// Runs `repairNoteStudentLinks` once on this device, from the launch pass:
    /// never while the first download from iCloud is under way
    /// (`FirstDownloadGate`), since notes and links still on their way down
    /// would read as missing, and never on a pass whose earlier steps left
    /// changes they couldn't save (those aren't this step's to save). It saves
    /// its own changes, and counts as done only once they're saved. Every
    /// device runs it; a link two devices add at once has one id
    /// (`CDNoteStudentLink.stableID`), so the deduplication folds the pair.
    ///
    /// Returns how many notes it changed, or nil when it didn't run or couldn't save.
    @discardableResult
    static func repairNoteStudentLinksIfDue(
        using context: NSManagedObjectContext,
        firstDownloadPending: Bool,
        defaults: UserDefaults = .standard
    ) -> Int? {
        let flag = UserDefaultsKeys.noteStudentLinkRepairDone
        guard !firstDownloadPending, !defaults.bool(forKey: flag), !context.hasChanges else { return nil }
        let changed = repairNoteStudentLinks(using: context)
        guard !context.hasChanges || context.safeSave() else {
            context.rollback()
            return nil
        }
        defaults.set(true, forKey: flag)
        return changed
    }
}

nonisolated extension UserDefaultsKeys {
    /// Set once the one-time repair of multi-child notes' student links has run
    /// and saved on this device (`DataCleanupService.repairNoteStudentLinksIfDue`).
    /// Per store environment, like the other launch-repair flags.
    static var noteStudentLinkRepairDone: String {
        CloudKitEnvironment.scoped("DataMigrations.noteStudentLinkRepairDone")
    }
}
