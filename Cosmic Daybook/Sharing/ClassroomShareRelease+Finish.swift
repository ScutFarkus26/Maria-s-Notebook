import CloudKit
import CoreData
import Foundation
import os

// Step 5 on its own: a run that stopped after its last batch's deletes were saved here
// leaves nothing to plan (the originals are gone from this Mac), so only iCloud's
// confirmation is left, from the list the run kept (`Environment.awaitingGone`).

nonisolated extension ClassroomShareRelease {

    /// Finishes a run that stopped between steps 4 and 5 of its last batch. A run that
    /// stopped before the list was kept leaves none to check. The deletes may never have
    /// gone (a save an export missed waits for the next launch, 2026-09-30), so when iCloud
    /// still has them and no export starts, one harmless change schedules one.
    static func finishStopped(
        stack: CoreDataStack,
        storeID: String,
        environment env: Environment
    ) async -> Report {
        var report = Report()
        let awaiting = env.awaitingGone()
        do {
            if !awaiting.isEmpty { try await checkCanGoOn(env) }
            report.unconfirmed = try await confirmLeftovers(awaiting, environment: env) { waiting in
                await env.exportIdle()
                if (try? await heldOnServer(waiting, environment: env))?.isEmpty != true {
                    let context = await runContext(stack)
                    let keeper = await nudgeTarget(stack: stack, storeID: storeID, environment: env)
                    try await makeSureItExports(after: Date(), nudging: keeper, context: context, environment: env)
                }
            }
        } catch {
            let stop = stopMessage(for: error)
            report.stoppedBecause = stop.message
            report.stopDetails = stop.details
            logger.error("Finishing the release stopped: \(stop.details, privacy: .public)")
        }
        return report
    }

    /// Confirms a stopped run's deletes on the awaiting list, and takes them off it
    /// (bug hunt 2026-11-02, #41). Those whose records are back in this Mac's store
    /// (`Environment.heldHere`: re-downloaded, say, after the child came back) come off
    /// first, unwaited: nothing here deletes them now, and a fresh plan takes again any that
    /// doesn't belong, so iCloud keeping them is no reason to wait, and every finish would end
    /// in "took too long". `beforeWaiting` hears the rest first. Those iCloud still hasn't
    /// confirmed when the wait runs out come off too, so a run can't be held unfinished by
    /// them for good: returns how many, for the guide to be told.
    static func confirmLeftovers(
        _ leftover: [CKRecord.ID],
        environment env: Environment,
        beforeWaiting: ([CKRecord.ID]) async throws -> Void = { _ in }
    ) async throws -> Int {
        guard !leftover.isEmpty else { return 0 }
        let back = await env.heldHere(leftover)
        if !back.isEmpty {
            logger.notice("\(back.count) record(s) awaiting iCloud are back in the notebook; not waiting on them")
            removeAwaitingGone(Array(back), environment: env)
        }
        let waiting = leftover.filter { !back.contains($0) }
        guard !waiting.isEmpty else { return 0 }
        try await beforeWaiting(waiting)
        do {
            try await waitForGone(waiting, environment: env)
        } catch RunError.timedOut(_) {
            logger.error("iCloud didn't confirm \(waiting.count) earlier delete(s) in time; taken off the list")
            removeAwaitingGone(waiting, environment: env)
            return waiting.count
        }
        removeAwaitingGone(waiting, environment: env)
        return 0
    }

    /// Waits until the server holds none of `records`. A record whose zone is gone counts as
    /// gone (the share was stopped, say): here, and only here, since a delete is all this
    /// confirms (`CloudKitServerCheck.ZoneMissing`).
    static func waitForGone(_ records: [CKRecord.ID], environment env: Environment) async throws {
        _ = try await waitFor("that last year's records left the share", environment: env) { () -> Bool? in
            try await heldOnServer(records, environment: env).isEmpty ? true : nil
        }
    }

    /// Of `records`, those the server still holds; one whose zone is gone isn't held.
    private static func heldOnServer(
        _ records: [CKRecord.ID], environment env: Environment
    ) async throws -> [CKRecord.ID: Date] {
        do {
            return try await env.serverRecords(records)
        } catch let missing as CloudKitServerCheck.ZoneMissing {
            return missing.found
        }
    }

    /// A Student or AttendanceRecord of the private store in no share, whose `modifiedAt`
    /// can be nudged to schedule an export (`makeSureItExports`): the oldest marks first,
    /// which a finished release has made private copies of. Nil when none is found.
    private static func nudgeTarget(
        stack: CoreDataStack, storeID: String, environment env: Environment
    ) async -> NSManagedObjectID? {
        let context = await stack.newBackgroundContext()
        let candidates: [NSManagedObjectID] = await context.perform {
            guard let store = store(storeID, in: context) else { return [] }
            var ids: [NSManagedObjectID] = []
            for (entity, key) in [("AttendanceRecord", "date"), ("Student", "dateWithdrawn")] {
                let request = NSFetchRequest<NSManagedObjectID>(entityName: entity)
                request.resultType = .managedObjectIDResultType
                request.affectedStores = [store]
                request.sortDescriptors = [NSSortDescriptor(key: key, ascending: true)]
                request.fetchLimit = 50
                ids += (try? context.fetch(request)) ?? []
            }
            return ids
        }
        guard !candidates.isEmpty, let zones = try? await env.shareZones(candidates) else { return nil }
        return candidates.first { zones[$0] == nil }
    }
}
