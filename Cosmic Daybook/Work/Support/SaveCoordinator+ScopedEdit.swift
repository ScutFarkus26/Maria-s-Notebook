// SaveCoordinator+ScopedEdit.swift
// One sheet's edit, saved on its own Save and taken back alone if the save fails.
//
// The work sheets (steps, sample works, practice sessions) used to change the
// view context and either never save it or save it and close regardless. A
// failed save then left their inserts sitting in the context, so a second
// Save made the step or the session twice. `rollback()` would be too broad:
// the view context can hold other screens' unsaved edits. This keeps the
// sheet's own changes in a `ContextMutationTransaction` and undoes only those.

import CoreData
import Foundation
import OSLog

extension SaveCoordinator {

    /// Runs `edit`, then saves `context` with `reason` (a log label). On a
    /// thrown edit or a failed save, undoes exactly what `edit` changed and
    /// returns false; the caller shows its own plain message, so the global
    /// alert stays quiet.
    @discardableResult
    func saveEdit(
        in context: NSManagedObjectContext, reason: String, _ edit: () throws -> Void
    ) -> Bool {
        let transaction = ContextMutationTransaction(context: context)
        do {
            try edit()
        } catch {
            transaction.rollback()
            Logger.work.warning("Edit failed before saving (\(reason, privacy: .public)): \(error)")
            return false
        }
        guard save(context, reason: reason, alertOnFailure: false) else {
            transaction.rollback()
            return false
        }
        transaction.commit()
        return true
    }
}
