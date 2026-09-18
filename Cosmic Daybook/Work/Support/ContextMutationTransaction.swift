import CoreData
import Foundation

/// Captures only the Core Data mutations made by one service operation.
///
/// The view context can already contain the guide's unsaved notes or edits, so
/// `rollback()` would be too broad. A temporary undo manager restores inserts,
/// updates, relationships, and deletes made after this transaction begins while
/// leaving the context's earlier pending changes alone.
///
/// Shared by the services that mutate work in several steps and must land all
/// of them or none: `PresentationFollowUpWorkService` and `WorkDeletionService`.
final class ContextMutationTransaction {
    private let context: NSManagedObjectContext
    private let previousUndoManager: UndoManager?
    private let operationUndoManager = UndoManager()
    private var isFinished = false

    init(context: NSManagedObjectContext) {
        self.context = context
        context.processPendingChanges()
        previousUndoManager = context.undoManager
        operationUndoManager.groupsByEvent = false
        context.undoManager = operationUndoManager
        operationUndoManager.beginUndoGrouping()
    }

    func commit() {
        guard !isFinished else { return }
        finishCapturing()
        operationUndoManager.removeAllActions()
        restorePreviousUndoManager()
    }

    func rollback() {
        guard !isFinished else { return }
        finishCapturing()
        if operationUndoManager.canUndo {
            operationUndoManager.undo()
            context.processPendingChanges()
        }
        operationUndoManager.removeAllActions()
        restorePreviousUndoManager()
    }

    private func finishCapturing() {
        context.processPendingChanges()
        if operationUndoManager.groupingLevel > 0 {
            operationUndoManager.endUndoGrouping()
        }
        isFinished = true
    }

    private func restorePreviousUndoManager() {
        context.undoManager = previousUndoManager
    }
}
