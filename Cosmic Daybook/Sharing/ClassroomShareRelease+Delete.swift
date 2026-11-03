import CloudKit
import CoreData
import Foundation
import os

// Step 4's deletes, and a twin cleanup's: each checked again in the delete's own pass and
// saved strictly, so a change made while the run goes (an edit in the main window, an import
// from iCloud) is never deleted with the record (bug hunt 2026-11-02, #37). A delete that
// finds one deletes nothing and says so (`RunError.changedDuringRun`); the batch checks
// again, bringing the change over, up to `changeRetries` times.

nonisolated extension ClassroomShareRelease {

    /// The context a run writes through: the app's own kind (`CoreDataStack.newBackgroundContext`),
    /// so its saves carry the app's author like every other writer's (bug hunt 2026-11-02, #53),
    /// but saving strictly, as the run always has: a change saved meanwhile refuses the save
    /// rather than being overwritten under the app's object-trump policy.
    static func runContext(_ stack: CoreDataStack) async -> NSManagedObjectContext {
        let context = await stack.newBackgroundContext()
        await context.perform { context.mergePolicy = NSMergePolicy.error }
        return context
    }

    /// Puts `records` on the awaiting list, then runs `delete`. Added to the list, never in
    /// place of it: an earlier stopped run's deletes on it still need iCloud's confirmation.
    /// When `delete` throws, nothing was deleted, and they come off it again.
    static func deleteListed(
        _ records: [CKRecord.ID], environment env: Environment, _ delete: () async throws -> Void
    ) async throws {
        let awaiting = env.awaitingGone()
        let onList = Set(awaiting)
        let added = records.filter { !onList.contains($0) }
        env.setAwaitingGone(awaiting + added)
        do {
            try await delete()
        } catch {
            removeAwaitingGone(added, environment: env)
            throw error
        }
    }

    /// Deletes the shared originals of `moves`, checked again in the delete's own pass.
    /// Nothing is deleted when a copy has gone from this Mac since it was checked (the run
    /// stops, `copyVanished`), or when an original changed after its copy was checked, an
    /// edit in the main window, say (`changedDuringRun`: the batch checks again, and step 3
    /// brings the change over).
    static func deleteOriginals(
        _ moves: [Move], keepers: [NSManagedObjectID: NSManagedObjectID], context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            context.refreshAllObjects()
            for move in moves {
                guard let keeper = keepers[move.source], let copy = try? context.existingObject(with: keeper) else {
                    throw RunError.copyVanished
                }
                if let original = try? context.existingObject(with: move.source), changedSinceCopied(original, copy) {
                    throw RunError.changedDuringRun
                }
            }
            for id in moves.flatMap(\.sharedRows) {
                // Gone already (another run finished it): nothing to delete.
                if let object = try? context.existingObject(with: id) { context.delete(object) }
            }
            try saveStrictly(context)
        }
    }

    /// Saves under the error merge policy: a change saved to one of the rows since this pass
    /// read it (an edit in the main window, an import from iCloud) refuses the save, where the
    /// app's object-trump policy would let a delete win and the change go with it. Such a
    /// refusal is `changedDuringRun`, rolled back: nothing was saved, and the batch checks
    /// again.
    static func saveStrictly(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        let policy = context.mergePolicy
        context.mergePolicy = NSMergePolicy.error
        defer { context.mergePolicy = policy }
        do {
            try context.save()
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSManagedObjectMergeError, NSPersistentStoreSaveConflictsError].contains(error.code) {
            context.rollback()
            logger.notice("A record changed as this pass saved; nothing was saved")
            throw RunError.changedDuringRun
        }
    }

    /// Whether `original` holds a change its copy lacks, which deleting it would lose: they
    /// differ by more than `modifiedAt` (a nudge moves only that), and the copy wasn't edited
    /// after it (then the copy's values stand, as in `checkCopies`).
    static func changedSinceCopied(_ original: NSManagedObject, _ copy: NSManagedObject) -> Bool {
        !sameAttributes(original, copy, except: ["modifiedAt"]) && !editedLater(copy, than: original)
    }
}
