import Foundation
import CoreData
import CloudKit

// MARK: - Off-MainActor Sharing
//
// `container.share(_:to:)` is documented as `async`, but its implementation
// blocks the calling thread on a kernel `__ulock_wait` until CloudKit's
// internal Share-Export task resolves. Every call therefore goes through a
// `Task.detached` on a fresh background context, so the ulock blocks a
// cooperative-pool worker rather than the MainActor's runloop.
//
// Both helpers here fire their faults with `existingObject(with:)` before
// handing objects to `container.share`. That is load-bearing, not stylistic —
// see the comment inside `shareOffMain`.

extension SharedStoreZoneRepair {

    /// True when `error` is CloudKit mirroring's "delegate never initialized"
    /// family. Once this appears, every subsequent `container.share(_:to:)`
    /// fails the same way and the store itself is usually unreadable, so the
    /// only safe move is to stop touching the container.
    ///
    /// - `134406` — request aborted because the mirroring delegate never
    ///   successfully initialized (the shape seen when another process
    ///   migrates the store file out from under a live one).
    /// - `134421` — export hit an unhandled exception analyzing history.
    /// - `256` on the store file — the sqlite file can no longer be opened.
    ///
    /// The message match is case-insensitive: Core Data spells the phrase
    /// lower-case inside 134406's `localizedDescription`.
    nonisolated static func indicatesDeadMirroringDelegate(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain,
           error.code == 134406 || error.code == 134421 || error.code == NSFileReadUnknownError {
            return true
        }
        return error.localizedDescription.range(
            of: "never successfully initialized",
            options: .caseInsensitive
        ) != nil
    }

    /// Runs `container.share(_:to:)` on a background context off the MainActor.
    /// The blocking ulock wait happens on a cooperative-pool worker, leaving
    /// the MainActor free to service view fetches and user input.
    ///
    /// `nonisolated` because we explicitly want this to run off MainActor.
    /// NSManagedObjectIDs are documented as thread-safe; the resolved
    /// NSManagedObjects only exist within the `performAndWait` block and the
    /// subsequent `container.share` await, both of which are bound to the
    /// freshly-created background context.
    nonisolated static func shareOffMain(
        chunkIDs: [NSManagedObjectID],
        share: CKShare,
        container: NSPersistentCloudKitContainer
    ) async throws {
        try await Task.detached {
            let bg = container.newBackgroundContext()
            // `object(with:)` hands back an *unfired* fault, so an unreadable
            // store does not surface here — it surfaces later, inside
            // `container.share`, where Core Data reports a failed fault by
            // raising an Objective-C exception instead of returning an error.
            // Swift cannot catch that, so the process aborts even though this
            // call sits inside a `do`/`catch`. Firing the faults up front with
            // `existingObject(with:)` turns the same failure into a catchable
            // Swift error, and the caller's per-record fallback then isolates
            // whichever record is bad.
            let objects: [NSManagedObject] = try bg.performAndWait {
                try chunkIDs.map { try bg.existingObject(with: $0) }
            }
            _ = try await container.share(objects, to: share)
        }.value
    }

    /// Creates a new CKShare seeded from `seedID` off the MainActor. Mirrors
    /// `shareOffMain` for the orphan-attach path; used by
    /// `ClassroomSharingService` to keep its share-create flow from
    /// monopolising the main thread on the same kernel `ulock` as the attach
    /// path.
    ///
    /// Returns the newly-created CKShare on success.
    nonisolated static func createShareOffMain(
        seedID: NSManagedObjectID,
        container: NSPersistentCloudKitContainer
    ) async throws -> CKShare {
        try await Task.detached {
            let bg = container.newBackgroundContext()
            // `existingObject(with:)` rather than `object(with:)` for the same
            // reason as `shareOffMain`: it fires the fault where a dead store
            // is a catchable Swift error rather than an uncatchable ObjC
            // exception raised from inside `container.share`.
            let seed: NSManagedObject = try bg.performAndWait {
                try bg.existingObject(with: seedID)
            }
            let (_, share, _) = try await container.share([seed], to: nil)
            return share
        }.value
    }
}
