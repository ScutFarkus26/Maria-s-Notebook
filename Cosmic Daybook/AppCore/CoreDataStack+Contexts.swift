import CoreData
import OSLog

extension CoreDataStack {
    // MARK: - View Context Configuration

    func configureViewContext() {
        let ctx = container.viewContext
        // Automatically merge remote changes into the view context
        ctx.automaticallyMergesChangesFromParent = true
        // Last-writer-wins: remote property values override local on conflict
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        // Tag transactions so the history processor can filter out our own writes
        ctx.transactionAuthor = PersistentHistoryProcessor.transactionAuthor
        // On macOS the view context gets a real NSUndoManager by default, which
        // records every insert/update/delete for the process lifetime — including
        // whole-table migrations and backup restores — and is never popped. The
        // three flows that need undo (command-bar capture, presentation follow-up,
        // immediate presentation recording) install their own local manager and
        // restore the previous value, so nil is the correct default here.
        ctx.undoManager = nil
        // Disable autosave — we use explicit saves via SaveCoordinator
        // (Mirrors the existing SwiftData behavior where autosave was disabled)
    }

    // MARK: - Background Context

    /// Creates a new background context for batch operations.
    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        ctx.transactionAuthor = PersistentHistoryProcessor.transactionAuthor
        return ctx
    }

    // MARK: - Remote Change Handling

    func handleRemoteChangeNotification() {
        // `.NSPersistentStoreRemoteChange` carries only a history token — never
        // the changed object IDs — so the entity filter that used to live here
        // always fell through to "invalidate everything", once per imported
        // batch. The history processor reads the transactions anyway and posts
        // `.schoolDayDataDidChange` only when a calendar entity was touched.
        guard let processor = historyProcessor else {
            // Stacks without history processing (Sample Class, tests) can't
            // tell what changed, so keep failing open there.
            NotificationCenter.default.post(name: .schoolDayDataDidChange, object: nil)
            return
        }
        Task {
            await processor.processRemoteChanges()
        }
    }
}
