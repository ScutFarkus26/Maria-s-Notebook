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
}
