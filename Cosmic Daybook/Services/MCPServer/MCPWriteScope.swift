//
//  MCPWriteScope.swift
//  Cosmic Daybook
//
//  What one MCP write takes back when it fails.
//
//  Every write runs on the app's view context, because the in-app services
//  it goes through do, and that context also holds the guide's own unsaved
//  edits: a sheet she has open, a note half typed. `rollback()` threw those
//  away along with the failed write (bug hunt 2026-10-11 #53). A scope
//  records exactly what the write changes, through the same
//  `ContextMutationTransaction` the work sheets use, and a failure undoes
//  only that. A separate background context, Apple's usual answer, would
//  bypass those services, so it isn't used.
//

import CoreData
import Foundation
import Synchronization

/// One MCP write's changes, undone alone if the write fails.
///
/// A save inside the write (a service that saves on its own, like the track
/// check after a mastery mark) is kept: the scope starts again after it, so a
/// later failure undoes only what is still unsaved, which is what
/// `rollback()` used to discard, less the guide's edits.
///
/// Scopes don't nest, and neither do they nest with a service's own
/// `ContextMutationTransaction` (`WorkDeletionService`): a tool built on such
/// a service relies on the service's undo instead.
@MainActor
final class MCPWriteScope {
    private let context: NSManagedObjectContext
    private var transaction: ContextMutationTransaction
    private var saveObserver: (any NSObjectProtocol)?
    /// Rows already edited when the scope (re)started: the guide's.
    private var updatedBefore: Set<NSManagedObjectID>

    init(context: NSManagedObjectContext) {
        self.context = context
        transaction = ContextMutationTransaction(context: context)
        updatedBefore = Set(context.updatedObjects.map(\.objectID))
        saveObserver = NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.didSaveObjectsNotification, object: context, queue: nil
        ) { [weak self] _ in
            // The view context saves on the main thread, inside the write.
            MainActor.assumeIsolated { self?.startAgainAfterSave() }
        }
    }

    /// The write finished: keep everything it changed.
    func commit() {
        stopObservingSaves()
        transaction.commit()
    }

    /// The write failed: take back what it changed since its last save.
    func undo() {
        stopObservingSaves()
        transaction.rollback()
        // A row the write touched and the undo put back can still read as
        // edited, with nothing changed; left so, the context would look as if
        // it had unsaved work. The guide's rows are left exactly as they are.
        for object in context.updatedObjects
        where !updatedBefore.contains(object.objectID) && object.changedValues().isEmpty {
            context.refresh(object, mergeChanges: false)
        }
    }

    private func startAgainAfterSave() {
        transaction.commit()
        transaction = ContextMutationTransaction(context: context)
        updatedBefore = Set(context.updatedObjects.map(\.objectID))
    }

    private func stopObservingSaves() {
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
        }
        saveObserver = nil
    }
}

extension MCPNotebookTools {
    /// Runs part of a write and says whether the context saved during it. A
    /// service that saves on its own (the track check after a mastery mark)
    /// puts everything before it on disk, where the scope can't take it back,
    /// so the write's reply must not say "nothing was changed" if a later
    /// save fails (bug hunt 2026-10-11 review).
    static func noticingSaves<Result>(
        of context: NSManagedObjectContext, _ body: () throws -> Result
    ) rethrows -> (result: Result, saved: Bool) {
        let flag = SaveFlag()
        let observer = NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.didSaveObjectsNotification, object: context, queue: nil
        ) { _ in
            flag.saved.withLock { $0 = true }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let result = try body()
        return (result, flag.saved.withLock { $0 })
    }
}

/// Set by the save observer in `noticingSaves`.
private final class SaveFlag: Sendable {
    let saved = Mutex(false)
}
