import CloudKit
import Foundation
import os

// Step 5 on its own: a run that stopped after its last batch's deletes were saved here
// leaves nothing to plan (the originals are gone from this Mac), so only iCloud's
// confirmation is left, from the list the run kept (`Environment.awaitingGone`).

nonisolated extension ClassroomShareRelease {

    /// Finishes a run that stopped between steps 4 and 5 of its last batch. A run that
    /// stopped before the list was kept leaves none to check.
    static func finishStopped(environment env: Environment) async -> Report {
        var report = Report()
        let awaiting = env.awaitingGone()
        do {
            if !awaiting.isEmpty {
                await env.exportIdle()
                try await waitForGone(awaiting, environment: env)
            }
            env.setAwaitingGone([])
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
}
