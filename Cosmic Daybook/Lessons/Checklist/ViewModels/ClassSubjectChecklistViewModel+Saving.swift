// ClassAreaChecklistViewModel+Saving.swift
// Every change the Checklist makes is saved through the app's `SaveCoordinator`. A
// save that fails used to go only to the log: the change stayed in the view context,
// the cell showed a mark that wasn't stored, and the next save anywhere could carry
// it, or fail again. Now a failed save takes back exactly this change (a
// `ContextMutationTransaction`, so the guide's other unsaved edits stay) and shows
// "Couldn't Save"; the grid then redraws from what is stored (bug hunt 2026-11-03 #13).

import CoreData
import Foundation

extension ClassAreaChecklistViewModel {

    /// Runs `change`, then saves. On a failed save, takes the change back, raises the
    /// "Couldn't Save" alert and returns false. `reason` goes to the log only.
    @discardableResult
    func saveChange(_ reason: String, context: NSManagedObjectContext, _ change: () -> Void) -> Bool {
        let transaction = ContextMutationTransaction(context: context)
        change()
        guard saveCoordinator.save(context, reason: reason) else {
            transaction.rollback()
            return false
        }
        transaction.commit()
        return true
    }
}
