// BackupSnapshotWatch.swift
// Keeps a streamed export a picture of one moment.
//
// The one-pass export (`collectPayload`) reads every entity type in a single
// main-actor turn, so nothing can change between its first fetch and its
// last. The streamed export hops off the main actor to encode each type, and
// other main-actor work runs in between: a CloudKit import merging in, an
// edit, an MCP write, a debounced save. If any of that could have changed
// what the view context's fetches return, the rows already collected and the
// rows still to come would describe different moments (a check-in without its
// work, a deleted work's check-ins). The writer asks this watch after every
// type, and on a change throws the streamed rows away and runs the one-pass
// export instead.

import CoreData
import Foundation

@MainActor
final class BackupSnapshotWatch {
    /// Edits on the view context (announced or still pending), saves on any
    /// context of its coordinator (the CloudKit import context included), and
    /// resets.
    private let flag: ManagedObjectChangeFlag
    private let entityNames: Set<String>
    private let coordinator: NSPersistentStoreCoordinator
    /// The SQLite stores, the only ones that keep persistent history.
    private let historyStores: [NSPersistentStore]
    /// Where their history stood when the watch began; nil with no SQLite
    /// store (an in-memory test stack) or no transaction yet.
    private let historyStart: NSPersistentHistoryToken?

    /// Starts watching every entity of the view context's model. Returns nil
    /// when the context holds unsaved edits: the flag's end-of-run check would
    /// report them whether or not they changed during the export, so that
    /// export uses the one-pass path, exactly as before.
    init?(viewContext: NSManagedObjectContext, center: NotificationCenter = .default) {
        guard !viewContext.hasChanges, let coordinator = viewContext.persistentStoreCoordinator else {
            return nil
        }
        let names = Set(coordinator.managedObjectModel.entitiesByName.keys)
        // Not the process-wide import signal: it names no store, so another
        // store's import (another workspace, or a test running alongside) would
        // throw away a stream this store never saw change. Every import it
        // reports arrives first as a save on this coordinator, which the flag
        // does watch, and the end-of-run history check backs that up.
        let flag = ManagedObjectChangeFlag(
            entityNames: names, context: viewContext, center: center, listensForImportSignal: false
        )
        // The flag starts dirty. A save it saw before this line committed before
        // the first fetch, so that fetch reads it like any other row.
        _ = flag.consume(pendingIn: viewContext)
        self.flag = flag
        self.entityNames = names
        self.coordinator = coordinator
        let stores = coordinator.persistentStores.filter { $0.type == NSSQLiteStoreType }
        self.historyStores = stores
        self.historyStart = stores.isEmpty ? nil : coordinator.currentPersistentHistoryToken(fromStores: stores)
    }

    /// Whether anything that could change a fetch's result happened since the
    /// watch began. Cheap: a bit, plus the context's pending sets when it has
    /// any. Ask it after each entity type is collected.
    func sawChange(in viewContext: NSManagedObjectContext) -> Bool {
        flag.consume(pendingIn: viewContext)
    }

    /// The last word, asked once every type is collected: the flag, then
    /// persistent history. A save posts its `DidSave` notification just after
    /// its commit, so one landing right before the last fetch could reach that
    /// fetch before it reaches the flag; the history cannot miss it.
    func sawChangeAtEnd(in viewContext: NSManagedObjectContext) -> Bool {
        if flag.consume(pendingIn: viewContext) { return true }
        guard !historyStores.isEmpty else { return false }
        guard let historyStart else {
            // No transaction when the watch began: any token now means the
            // first one was committed during the export.
            return coordinator.currentPersistentHistoryToken(fromStores: historyStores) != nil
        }
        return historyTouchesEntities(since: historyStart, in: viewContext)
    }

    /// Whether any transaction after `token` changed a row of the model's
    /// entities. CloudKit's own bookkeeping lives outside the model and does
    /// not count. Unreadable history (purged past the token) counts as a change.
    private func historyTouchesEntities(
        since token: NSPersistentHistoryToken,
        in context: NSManagedObjectContext
    ) -> Bool {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.resultType = .transactionsAndChanges
        do {
            guard let result = try context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                return true
            }
            return transactions.contains { transaction in
                guard let changes = transaction.changes else { return true }
                return changes.contains { change in
                    guard let name = change.changedObjectID.entity.name else { return true }
                    return entityNames.contains(name)
                }
            }
        } catch {
            return true
        }
    }
}
