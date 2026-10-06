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
        container: NSPersistentCloudKitContainer,
        storeID: String,
        environment env: Environment
    ) async -> Report {
        var report = Report()
        let awaiting = env.awaitingGone()
        do {
            if !awaiting.isEmpty {
                try await checkCanGoOn(env)
                await env.exportIdle()
                if (try? await env.serverRecords(awaiting))?.isEmpty != true {
                    let context = container.newBackgroundContext()
                    let keeper = await nudgeTarget(container: container, storeID: storeID, environment: env)
                    try await makeSureItExports(after: Date(), nudging: keeper, context: context, environment: env)
                }
                try await waitForGone(awaiting, environment: env)
            }
            removeAwaitingGone(awaiting, environment: env)
        } catch {
            let stop = stopMessage(for: error)
            report.stoppedBecause = stop.message
            report.stopDetails = stop.details
            logger.error("Finishing the release stopped: \(stop.details, privacy: .public)")
        }
        return report
    }

    /// Waits until the server holds none of `records`.
    static func waitForGone(_ records: [CKRecord.ID], environment env: Environment) async throws {
        _ = try await waitFor("that last year's records left the share", environment: env) { () -> Bool? in
            try await env.serverRecords(records).isEmpty ? true : nil
        }
    }

    /// A Student or AttendanceRecord of the private store in no share, whose `modifiedAt`
    /// can be nudged to schedule an export (`makeSureItExports`): the oldest marks first,
    /// which a finished release has made private copies of. Nil when none is found.
    private static func nudgeTarget(
        container: NSPersistentCloudKitContainer, storeID: String, environment env: Environment
    ) async -> NSManagedObjectID? {
        let context = container.newBackgroundContext()
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
