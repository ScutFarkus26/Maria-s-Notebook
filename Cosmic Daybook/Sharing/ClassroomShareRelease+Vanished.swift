import CloudKit
import CoreData
import Foundation
import os

// Step 3, checking the copies, and its other case: an original gone from this Mac partway
// through a batch. If another device deleted it, the private copy made from it would bring
// the record back, so the copy goes too, but only once the CloudKit server says the record
// is gone from the share. Gone here while iCloud still has it (a store being re-imported,
// say) is no proof of a delete: the copy is kept and the run stops.

nonisolated extension ClassroomShareRelease {

    /// Checks every copy is still here and matches its original; returns the copies it had
    /// to update, and the moves whose shared rows have all left this Mac (`settleVanished`).
    /// A copy edited after its original (a stopped run's, which the guide kept using) keeps
    /// its own values: the original is about to go.
    static func checkCopies(
        _ moves: [Move], keepers: [NSManagedObjectID: NSManagedObjectID], context: NSManagedObjectContext
    ) async throws -> (changed: [NSManagedObjectID], vanished: [Move]) {
        try await context.perform {
            context.refreshAllObjects()
            var changed: [NSManagedObjectID] = []
            var vanished: [Move] = []
            for move in moves {
                guard let keeper = keepers[move.source] else { continue }
                guard let copy = try? context.existingObject(with: keeper) else { throw RunError.copyVanished }
                guard let original = try? context.existingObject(with: move.source) else {
                    if move.sharedRows.allSatisfy({ (try? context.existingObject(with: $0)) == nil }) {
                        vanished.append(move)
                    }
                    continue
                }
                if !sameAttributes(original, copy), !editedLater(copy, than: original) {
                    copyAttributes(from: original, to: copy)
                    changed.append(keeper)
                }
            }
            if context.hasChanges { try context.save() }
            return (changed, vanished)
        }
    }

    /// Settles the moves whose shared rows all left this Mac during the batch. Those iCloud
    /// no longer has were deleted elsewhere: their private copies are deleted too. If any
    /// other is left, its copy is kept and the run stops. Returns the sources of the moves
    /// settled, which step 4 skips. `records` are the shared rows' iCloud records, read when
    /// the batch began.
    static func settleVanished(
        _ vanished: [Move],
        records: [NSManagedObjectID: CKRecord.ID],
        keepers: [NSManagedObjectID: NSManagedObjectID],
        context: NSManagedObjectContext,
        environment env: Environment
    ) async throws -> Set<NSManagedObjectID> {
        guard !vanished.isEmpty else { return [] }
        let deleted = try await deletedElsewhere(vanished, records: records, environment: env)
        if !deleted.isEmpty {
            let copies = Set(deleted.compactMap { keepers[$0.source] })
            await env.exportIdle()
            try await context.perform {
                for id in copies {
                    if let copy = try? context.existingObject(with: id) { context.delete(copy) }
                }
                if context.hasChanges { try context.save() }
            }
            let saved = Date() // once the save has returned, as in `runBatch`
            let survivor = keepers.values.first { !copies.contains($0) }
            try await makeSureItExports(after: saved, nudging: survivor, context: context, environment: env)
            logger.notice("\(deleted.count) record(s) deleted elsewhere during the run; their copies went too")
        }
        guard deleted.count == vanished.count else {
            logger.error("\(vanished.count - deleted.count) record(s) left this Mac but not iCloud; copies kept")
            throw RunError.originalVanished
        }
        return Set(deleted.map(\.source))
    }

    /// Of `vanished`, the moves none of whose shared rows the server still holds. A move
    /// missing a record in `records` can't be checked, and isn't counted as deleted. A zone
    /// that's gone (the share stopped) throws rather than answering, so the copies stay.
    private static func deletedElsewhere(
        _ vanished: [Move], records: [NSManagedObjectID: CKRecord.ID], environment env: Environment
    ) async throws -> [Move] {
        let checkable = vanished.filter { move in move.sharedRows.allSatisfy { records[$0] != nil } }
        let ids = checkable.flatMap { move in move.sharedRows.compactMap { records[$0] } }
        guard !ids.isEmpty else { return [] }
        let onServer = try await waitFor("whether iCloud still has the vanished records", environment: env) {
            () -> [CKRecord.ID: Date]? in try await env.serverRecords(ids)
        }
        return checkable.filter { move in
            move.sharedRows.allSatisfy { row in records[row].map { onServer[$0] == nil } ?? false }
        }
    }
}
