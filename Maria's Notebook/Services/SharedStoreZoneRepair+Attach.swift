import Foundation
import CoreData
import CloudKit
import OSLog

// MARK: - Attaching orphans to the share
//
// Once detection (`+Detection`) has the IDs of records outside every CKShare
// zone and `run` has found the share to put them in, this is the part that
// actually moves them: chunked `container.share(_:to:)` calls off the main
// actor (`+Sharing`), a per-record fallback for a chunk that fails, and the
// two kill switches that stop a hopeless pass early.

extension SharedStoreZoneRepair {

    // MARK: - Attachment

    /// Attaches orphans to the share in **chunks**. NSPersistentCloudKitContainer's
    /// `Share-Export` task has an internal timeout, and attempting to attach
    /// thousands of records in one batch reliably trips it ("Share-Export
    /// timed out"). Chunking keeps each request small enough that the export
    /// scheduler finishes within its budget; per-chunk per-record fallback
    /// still isolates pathological records.
    ///
    /// `container.share(_:to:)` is documented as `async` but its implementation
    /// blocks the calling thread on a kernel `__ulock_wait` until CloudKit's
    /// internal Share-Export task resolves. To keep the MainActor responsive
    /// we marshal each share call through a `Task.detached` running against a
    /// background context — the ulock then blocks a cooperative-pool worker
    /// instead of the MainActor's runloop.
    ///
    /// We yield to the actor between chunks so the bootstrapper can interleave
    /// other work, and log progress so a multi-minute attach is visible in
    /// Console.
    func attachOrphans(
        _ orphanIDs: [NSManagedObjectID],
        to share: CKShare,
        container: NSPersistentCloudKitContainer
    ) async -> [NSManagedObjectID] {
        let chunkSize = 200
        let attachMsg = "Attaching \(orphanIDs.count) orphan record(s) in chunks of \(chunkSize)"
        Self.logger.notice("\(attachMsg, privacy: .public)")

        var failures: [NSManagedObjectID] = []
        var successCount = 0
        let chunkCount = (orphanIDs.count + chunkSize - 1) / chunkSize

        for (chunkIndex, start) in stride(from: 0, to: orphanIDs.count, by: chunkSize).enumerated() {
            let end = min(start + chunkSize, orphanIDs.count)
            let chunkIDs = Array(orphanIDs[start..<end])

            do {
                try await Self.shareOffMain(chunkIDs: chunkIDs, share: share, container: container)
                successCount += chunkIDs.count
                let chunkMsg = "Chunk \(chunkIndex + 1)/\(chunkCount): attached \(chunkIDs.count)" +
                    " record(s) (running total: \(successCount)/\(orphanIDs.count))"
                Self.logger.notice("\(chunkMsg, privacy: .public)")
                await Task.yield()
                continue
            } catch {
                let ns = error as NSError
                let failMsg = "Chunk \(chunkIndex + 1)/\(chunkCount) batch attach failed: " +
                    "domain=\(ns.domain) code=\(ns.code) description=\(ns.localizedDescription)" +
                    " userInfo=\(ns.userInfo)."
                Self.logger.warning("\(failMsg, privacy: .public)")

                if let reason = abortReason(for: ns) {
                    failures.append(contentsOf: orphanIDs[start..<orphanIDs.count])
                    let abortMsg = "Orphan attachment aborted (\(reason)): \(successCount) succeeded, " +
                        "\(failures.count) deferred"
                    Self.logger.error("\(abortMsg, privacy: .public)")
                    return failures
                }
            }

            // The whole-chunk call failed for a reason that might be specific
            // to one bad record, so retry the chunk one record at a time.
            let fallback = await attachIndividually(chunkIDs, to: share, container: container)
            successCount += fallback.succeeded
            failures.append(contentsOf: fallback.failures)

            if fallback.delegateDied {
                failures.append(contentsOf: fallback.untried)
                failures.append(contentsOf: orphanIDs[end..<orphanIDs.count])
                let abortMsg = "Orphan attachment aborted (mirroring delegate dead): " +
                    "\(successCount) succeeded, \(failures.count) deferred"
                Self.logger.error("\(abortMsg, privacy: .public)")
                return failures
            }

            // Yield between chunks so we don't monopolise the MainActor for
            // minutes and so any cancellation has a chance to propagate.
            await Task.yield()
        }

        let completeMsg = "Orphan attachment complete: \(successCount) succeeded, \(failures.count) unrecoverable"
        Self.logger.notice("\(completeMsg, privacy: .public)")
        return failures
    }

    /// Why a whole-chunk failure should abandon the entire pass rather than
    /// fall back to per-record retries, or `nil` when per-record is worth a go.
    ///
    /// Both cases here fail identically for every remaining record, so retrying
    /// them one at a time buys nothing — and in the dead-delegate case the
    /// retries are what eventually walk into `container.share`'s uncatchable
    /// Objective-C exception (see `shareOffMain`).
    ///
    /// Returning a reason also arms the matching kill switch, because both
    /// conditions outlive this pass: the session-wide mirroring-delegate flag
    /// (cleared only by relaunching) or the 24-hour circuit breaker.
    private func abortReason(for error: NSError) -> String? {
        if Self.indicatesDeadMirroringDelegate(error) {
            CloudKitSyncStatusService.shared.mirroringDelegateFailed = true
            return "mirroring delegate never initialized, code \(error.code)"
        }

        // CloudKit's Share-Export timeout. Trip the circuit breaker so we don't
        // burn another ten-minute ulock wait per remaining record; the user can
        // retry from Settings → Repair Sync Errors.
        if error.domain == NSCocoaErrorDomain && error.code == 134060 {
            Self.tripCircuitBreakerOnTimeout()
            return "Share-Export timed out, manual Repair required"
        }

        return nil
    }

    /// Per-record retry for one chunk, isolating a single pathological record
    /// instead of losing the whole chunk to it.
    private func attachIndividually(
        _ chunkIDs: [NSManagedObjectID],
        to share: CKShare,
        container: NSPersistentCloudKitContainer
    ) async -> ChunkFallbackResult {
        var result = ChunkFallbackResult()

        for (index, orphanID) in chunkIDs.enumerated() {
            do {
                try await Self.shareOffMain(chunkIDs: [orphanID], share: share, container: container)
                result.succeeded += 1
            } catch {
                result.failures.append(orphanID)
                let ns = error as NSError
                let uri = orphanID.uriRepresentation().absoluteString
                let errMsg = "Per-record attach failed for \(uri): " +
                    "domain=\(ns.domain) code=\(ns.code)" +
                    " description=\(ns.localizedDescription) userInfo=\(ns.userInfo)"
                Self.logger.error("\(errMsg, privacy: .public)")

                if Self.indicatesDeadMirroringDelegate(ns) {
                    CloudKitSyncStatusService.shared.mirroringDelegateFailed = true
                    result.delegateDied = true
                    result.untried = Array(chunkIDs[(index + 1)...])
                    return result
                }
            }
        }

        return result
    }

    /// Tally from one chunk's per-record retry pass.
    private struct ChunkFallbackResult {
        var succeeded = 0
        /// Records that were attempted and failed.
        var failures: [NSManagedObjectID] = []
        /// Records skipped because the pass aborted. Only ever non-empty when
        /// ``delegateDied`` is true.
        var untried: [NSManagedObjectID] = []
        /// True when the mirroring delegate died mid-chunk, meaning no further
        /// `container.share` call can succeed this session.
        var delegateDied = false
    }
}
