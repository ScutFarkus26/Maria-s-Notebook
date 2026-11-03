import CloudKit
import CoreData
import Foundation
import os

// Records a stopped run left on both sides of the share that belong in it after all: a child
// who came back before the run was finished, or marks an earlier school-year start took back
// in (`TwinCleanup`; bug hunt 2026-11-02, #38). The shared original stays, so the assistants
// keep the record; its private copies go, in confirmed steps like a move's, the other way:
//
// 1. iCloud has every shared original;
// 2. whatever a private copy was edited with after its original is brought over to it;
// 3. the private copies are deleted, each only while its original is still here and holds
//    every such edit, checked in the delete's own pass;
// 4. iCloud no longer has them.
//
// iCloud never holds fewer than one copy: the shared one is confirmed there before any
// private copy goes.

nonisolated extension ClassroomShareRelease {

    /// One batch of twin cleanups, in the four steps.
    static func runTwinCleanup(_ batch: Batch, stack: CoreDataStack, environment env: Environment) async throws {
        try await checkCanGoOn(env)
        let cleanups = batch.twinCleanups
        let originals = cleanups.map(\.shared)
        let context = await runContext(stack)
        // The copies' iCloud records, read while they're here. One never exported has none,
        // and nothing to wait for.
        let twinRecords = Array(await env.recordIDs(cleanups.flatMap(\.twins)).values)

        // 1. iCloud has every shared original.
        var confirmed = try await waitForSharedOriginals(originals, environment: env)
        await env.afterStep(.sharedConfirmed, batch)

        var retries = 0
        while true {
            do {
                // 2. Edits made to a copy after its original are brought over to the original.
                await env.exportIdle()
                let changed = try await carryTwinEdits(cleanups, context: context)
                if !changed.isEmpty {
                    try await makeSureItExports(
                        after: Date(), nudging: changed.first, context: context, environment: env
                    )
                    let newer = try await waitForNewerCopies(changed, than: confirmed, environment: env)
                    confirmed.merge(newer) { $1 }
                }
                await env.afterStep(.twinsChecked, batch)

                // 3. The private copies go, on the awaiting list first, as a move's originals.
                await env.exportIdle()
                try await deleteListed(twinRecords, environment: env) {
                    try await deleteTwins(cleanups, context: context)
                }
                break
            } catch RunError.changedDuringRun where retries < changeRetries {
                retries += 1
                logger.notice("A record changed as the cleanup saved; checking again")
            }
        }
        try await makeSureItExports(after: Date(), nudging: originals.first, context: context, environment: env)
        await env.afterStep(.twinsDeleted, batch)

        // 4. iCloud no longer has them.
        try await waitForGone(twinRecords, environment: env)
        removeAwaitingGone(twinRecords, environment: env)
        await env.afterStep(.twinsGone, batch)
    }

    // MARK: - The steps

    /// Waits until the server holds every shared original; returns their modification dates.
    private static func waitForSharedOriginals(
        _ originals: [NSManagedObjectID], environment env: Environment
    ) async throws -> [NSManagedObjectID: Date] {
        try await waitFor("the shared records", environment: env) { () -> [NSManagedObjectID: Date]? in
            let records = await env.recordIDs(originals)
            guard records.count == originals.count else { throw RunError.originalNotMirrored }
            let onServer = try await env.serverRecords(Array(records.values))
            guard onServer.count == records.count else { return nil }
            return records.compactMapValues { onServer[$0] }
        }
    }

    /// Brings over to each shared original the values of a private copy edited after it
    /// (the latest such copy's); returns the originals it changed. Without a later edit the
    /// original's values stand: it is the one the assistants see. An original gone from this
    /// Mac stops the run, its copies kept: another device may have deleted it. Saved strictly:
    /// an edit to an original made meanwhile is checked again, not overwritten.
    private static func carryTwinEdits(
        _ cleanups: [TwinCleanup], context: NSManagedObjectContext
    ) async throws -> [NSManagedObjectID] {
        try await context.perform {
            context.refreshAllObjects()
            var changed: [NSManagedObjectID] = []
            for cleanup in cleanups {
                guard let original = try? context.existingObject(with: cleanup.shared) else {
                    throw RunError.sharedOriginalGone
                }
                let edited = cleanup.twins
                    .compactMap { try? context.existingObject(with: $0) }
                    .filter { holdsLaterEdit($0, than: original) }
                    .max { stamp($0) < stamp($1) }
                guard let edited else { continue }
                copyAttributes(from: edited, to: original)
                changed.append(cleanup.shared)
            }
            try saveStrictly(context)
            return changed
        }
    }

    /// Deletes the private copies, checked again in the delete's own pass. Nothing is
    /// deleted when an original has left this Mac (the run stops, `sharedOriginalGone`), or
    /// when a copy was edited after the check (`changedDuringRun`: the batch checks again,
    /// and step 2 brings the edit over).
    private static func deleteTwins(_ cleanups: [TwinCleanup], context: NSManagedObjectContext) async throws {
        try await context.perform {
            context.refreshAllObjects()
            for cleanup in cleanups {
                guard let original = try? context.existingObject(with: cleanup.shared) else {
                    throw RunError.sharedOriginalGone
                }
                for id in cleanup.twins {
                    if let twin = try? context.existingObject(with: id), holdsLaterEdit(twin, than: original) {
                        throw RunError.changedDuringRun
                    }
                }
            }
            for id in cleanups.flatMap(\.twins) {
                // Gone already (another device deleted it): nothing to delete.
                if let twin = try? context.existingObject(with: id) { context.delete(twin) }
            }
            try saveStrictly(context)
        }
    }

    // MARK: - Helpers

    /// Whether a private copy holds an edit its shared original lacks: stamped after it
    /// (`editedLater`), and different by more than `modifiedAt`.
    static func holdsLaterEdit(_ twin: NSManagedObject, than original: NSManagedObject) -> Bool {
        editedLater(twin, than: original) && !sameAttributes(twin, original, except: ["modifiedAt"])
    }

    private static func stamp(_ object: NSManagedObject) -> Date {
        guard object.entity.attributesByName["modifiedAt"] != nil else { return .distantPast }
        return object.value(forKey: "modifiedAt") as? Date ?? .distantPast
    }
}
