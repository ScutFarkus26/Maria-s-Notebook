import Foundation
@preconcurrency import CoreData
import CloudKit
import OSLog

/// Puts classroom records into the one classroom share.
///
/// Three callers, all deliberate, none sweeping: the lead guide's explicit
/// "Set Up Classroom Sharing" (everything, once), `SharedStoreOrphanGuard`
/// (only what this device just created), and the Daybook Assistant (its own
/// new marks). Nothing here looks for records that merely *look* unshared.
///
/// Records already in a share are never moved: `container.share(_:to:)` "will
/// fail if … already shared", and on 2026-09-27 trying it killed the mirroring
/// delegate for the session. `unshared(_:container:)` filters them out first.
///
/// `container.share(_:to:)` is documented as `async`, but it blocks the
/// calling thread on a kernel `__ulock_wait` until CloudKit's internal
/// Share-Export task resolves. Every call therefore runs in a detached task on
/// a fresh background context, so the wait blocks a cooperative-pool worker
/// rather than the main actor.
nonisolated enum ClassroomShareAttach {

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CosmicDaybook",
        category: "ClassroomShareAttach"
    )

    /// Records per `container.share(_:to:)` call. The Share-Export task has an
    /// internal timeout that thousands of records in one call reliably trip.
    static let chunkSize = 200

    /// How one attach pass went.
    struct Outcome: Sendable {
        var attached = 0
        /// Records that were tried and failed, plus any left untried after the
        /// pass stopped early. Callers keep these to try again later.
        var failed: [NSManagedObjectID] = []
        /// Set when the pass stopped early and why, in plain words (it is
        /// shown): the mirroring delegate died (nothing more can succeed this
        /// session), CloudKit timed out, iCloud couldn't be reached or was
        /// busy, or `Steps.stopReason` said to stop.
        var stoppedBecause: String?
        var mirroringDelegateDied = false
        /// The pass stopped because iCloud couldn't be reached
        /// (`indicatesNoConnection`): the Daybook Assistant rests briefly and
        /// tells her the marks go once she's back online.
        var noConnection = false
        /// CloudKit asked for this many seconds before the next try
        /// (`CKErrorRetryAfterKey`).
        var retryAfter: TimeInterval?

        /// Notes why the pass stopped on `error`.
        mutating func stop(_ reason: String, on error: NSError) {
            stoppedBecause = reason
            mirroringDelegateDied = ClassroomShareAttach.indicatesDeadMirroringDelegate(error)
            noConnection = ClassroomShareAttach.indicatesNoConnection(error)
            retryAfter = ClassroomShareAttach.retryAfter(in: error)
        }
    }

    // MARK: - Finding the share

    /// The classroom share among the shares in `store`: the pinned one. With
    /// `onlyShareFallback`, a store holding exactly one share answers with it
    /// when nothing is pinned yet — safe only where one share is all there can
    /// be (an assistant's shared store in the two-zone layout).
    static func classroomShare(
        in store: NSPersistentStore,
        container: NSPersistentCloudKitContainer,
        pinContext: NSManagedObjectContext,
        onlyShareFallback: Bool = false
    ) throws -> CKShare? {
        let shares = try container.fetchShares(in: store)
        return choose(among: shares, pinContext: pinContext, onlyShareFallback: onlyShareFallback)
    }

    /// The same answer with the shares read off the caller's actor, for a
    /// caller on the main actor. `pinContext` is read on the caller's actor.
    static func classroomShare(
        inStoreWithIdentifier storeIdentifier: String,
        container: NSPersistentCloudKitContainer,
        pinContext: NSManagedObjectContext,
        onlyShareFallback: Bool = false
    ) async throws -> CKShare? {
        let shares = try await shares(inStoreWithIdentifier: storeIdentifier, container: container)
        return choose(among: shares, pinContext: pinContext, onlyShareFallback: onlyShareFallback)
    }

    /// `container.fetchShares(in:)` for the store with `storeIdentifier`, off
    /// the caller's actor: it is a synchronous read of the store's CloudKit
    /// metadata, which waits while an export or import holds the store, and so
    /// stalls the UI mid-sync when run on the main thread.
    @concurrent
    static func shares(
        inStoreWithIdentifier storeIdentifier: String,
        container: NSPersistentCloudKitContainer
    ) async throws -> [CKShare] {
        let stores = container.persistentStoreCoordinator.persistentStores
        guard let store = stores.first(where: { $0.identifier == storeIdentifier }) else { return [] }
        return try container.fetchShares(in: store)
    }

    private static func choose(
        among shares: [CKShare],
        pinContext: NSManagedObjectContext,
        onlyShareFallback: Bool
    ) -> CKShare? {
        if let pinned = CDClassroomMembership.classroomShare(among: shares, in: pinContext) {
            return pinned
        }
        // Only when nothing is pinned: with a pin and no share matching it
        // (taken out of that class, one other share left behind), the records
        // wait rather than go into another class's share.
        if onlyShareFallback, shares.count == 1, CDClassroomMembership.pinnedZoneName(in: pinContext) == nil {
            return shares.first
        }
        return nil
    }

    /// The records among `ids` that belong to no share yet. Throws when
    /// CloudKit can't say, which callers treat as "try later", never as
    /// "none of them are shared".
    @concurrent
    static func unshared(
        _ ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer
    ) async throws -> [NSManagedObjectID] {
        guard !ids.isEmpty else { return [] }
        let inShare = try container.fetchShares(matching: ids)
        return ids.filter { inShare[$0] == nil }
    }

    // MARK: - Attaching

    /// What one attach pass asks of CloudKit, so a test can stand in for it.
    struct Steps: Sendable {
        /// The records among these in no share yet (`unshared`); throws when
        /// CloudKit can't say.
        var unshared: @Sendable ([NSManagedObjectID]) async throws -> [NSManagedObjectID]
        /// Puts these records into the share (`container.share(_:to:)`).
        var share: @Sendable ([NSManagedObjectID]) async throws -> Void
        /// Asked before each call to `share`: why the pass must stop now, as
        /// a phrase that finishes "…couldn't be added because …", or nil to
        /// go on. On the notebook, the sync status's: sync can stop, or a
        /// hold start, while the chunks of one pass go out, and the check
        /// once per pass let them all go (bug hunt 2026-10-10, #6).
        var stopReason: @Sendable () async -> String? = { nil }

        /// CloudKit's, for `share` in `container`. Each call is handed the
        /// latest copy of the share (`latestForAttach`), never the one passed
        /// in, and isn't made at all when that read finds iCloud can't be
        /// reached: offline, `share(_:to:)` waits for the server rather than
        /// failing, so the pass would never learn it was offline.
        static func live(
            _ share: CKShare,
            container: NSPersistentCloudKitContainer,
            stopReason: @escaping @Sendable () async -> String? = { nil }
        ) -> Steps {
            Steps(
                unshared: { ids in try await ClassroomShareAttach.unshared(ids, container: container) },
                share: { ids in
                    let latest = try await ClassroomShareAttach.latestForAttach(share, container: container)
                    try await ClassroomShareAttach.shareOffMain(ids, to: latest, container: container)
                },
                stopReason: stopReason
            )
        }
    }

    /// Attaches `ids` to `share` in chunks, retrying a failed chunk one record
    /// at a time so one bad record doesn't cost the rest. Stops early — with
    /// the remainder in `failed` — when the delegate dies, CloudKit times
    /// out, or `stopReason`, asked before every call, gives one.
    ///
    /// A record goes into the share with everything related to it (a staple
    /// takes its history along), so one can already be in by the time its own
    /// call comes up, and another pass (on this device or another) can have
    /// shared it since the caller looked. Before every call, the first
    /// included, what is now shared is dropped from it (and counted as
    /// attached): `share(_:to:)` is never asked to share a record twice. If
    /// CloudKit can't say, that call's records wait as failed.
    ///
    /// Each call is handed the latest copy of the share (`current`), never the
    /// one passed in: every `container.share(_:to:)` saves the share record,
    /// so after the first chunk the caller's copy carries an old change tag.
    /// Core Data then retries the export forever on "Server Record Changed"
    /// (oplock) and the call never returns — the 2026-09-28 Production setup
    /// hung that way after 400 of 3,226 records.
    static func attach(
        _ ids: [NSManagedObjectID],
        to share: CKShare,
        container: NSPersistentCloudKitContainer,
        stopReason: @escaping @Sendable () async -> String? = { nil }
    ) async -> Outcome {
        await attach(ids, using: .live(share, container: container, stopReason: stopReason))
    }

    /// `attach(_:to:container:stopReason:)` with CloudKit's part as `steps`.
    static func attach(_ ids: [NSManagedObjectID], using steps: Steps) async -> Outcome {
        var outcome = Outcome()
        var start = 0
        while start < ids.count {
            if let reason = await steps.stopReason() {
                logger.notice("Attach stopped before a chunk: \(reason, privacy: .public)")
                outcome.stoppedBecause = reason
                outcome.failed += ids[start...]
                return outcome
            }
            let end = min(start + chunkSize, ids.count)
            let taken = Array(ids[start..<end])
            guard let chunk = await stillOutside(taken, steps: steps, outcome: &outcome) else {
                outcome.failed += taken
                start = end
                continue
            }
            if !chunk.isEmpty {
                do {
                    try await steps.share(chunk)
                    outcome.attached += chunk.count
                } catch {
                    let ns = error as NSError
                    logger.warning("Chunk attach failed: \(ns.domain, privacy: .public) \(ns.code, privacy: .public)")
                    if let reason = stopReason(for: ns) {
                        outcome.stop(reason, on: ns)
                        outcome.failed += chunk + ids[end...]
                        return outcome
                    }
                    let stopped = await attachOneByOne(chunk, steps: steps, outcome: &outcome)
                    if stopped {
                        outcome.failed += ids[end...]
                        return outcome
                    }
                }
            }
            await Task.yield()
            start = end
        }
        return outcome
    }

    /// After a chunk failed, each of its records on its own. Returns true when
    /// the pass must stop, with what's left in `failed`.
    private static func attachOneByOne(
        _ chunk: [NSManagedObjectID],
        steps: Steps,
        outcome: inout Outcome
    ) async -> Bool {
        for (index, id) in chunk.enumerated() {
            if let reason = await steps.stopReason() {
                outcome.stoppedBecause = reason
                outcome.failed += chunk[index...]
                return true
            }
            guard let single = await stillOutside([id], steps: steps, outcome: &outcome) else {
                outcome.failed.append(id)
                continue
            }
            guard !single.isEmpty else { continue }
            do {
                try await steps.share(single)
                outcome.attached += 1
            } catch {
                let failure = error as NSError
                outcome.failed.append(id)
                if let reason = stopReason(for: failure) {
                    outcome.stop(reason, on: failure)
                    outcome.failed += chunk[(index + 1)...]
                    return true
                }
            }
        }
        return false
    }

    /// The records among `candidates` still in no share. The others went in
    /// with a record related to them, and count as attached. Nil when CloudKit
    /// can't say.
    private static func stillOutside(
        _ candidates: [NSManagedObjectID],
        steps: Steps,
        outcome: inout Outcome
    ) async -> [NSManagedObjectID]? {
        guard let outside = try? await steps.unshared(candidates) else { return nil }
        outcome.attached += candidates.count - outside.count
        return outside
    }

    /// The latest copy of `share`: the server's when it answers, since the
    /// server's change tag is the one a save is checked against; otherwise the
    /// store's; `share` itself when neither has it. The guide owns the share
    /// (private database); an assistant sees it in the shared database.
    /// Off the caller's actor: offline, the store's copy is read with
    /// `fetchShares(in:)`, which waits while an export holds the store.
    @concurrent
    static func current(_ share: CKShare, container: NSPersistentCloudKitContainer) async -> CKShare {
        let cloud = await CloudKitConfigurationService.container
        let database = share.recordID.zoneID.ownerName == CKCurrentUserDefaultName
            ? cloud.privateCloudDatabase
            : cloud.sharedCloudDatabase
        if let fresh = try? await database.record(for: share.recordID) as? CKShare {
            return fresh
        }
        let stored = (try? container.fetchShares(in: nil)) ?? []
        return stored.first { $0.recordID == share.recordID } ?? share
    }

    /// How long an attach's read of the share waits on the server: with no
    /// data for `request`, or `resource` in all. CloudKit's own defaults let
    /// a weak link hold a chunk for a minute before its call even began.
    static let attachFetchTimeout = (request: 15.0, resource: 30.0)

    /// The latest copy of `share` for an attach: the server's, read with a
    /// short timeout (`attachFetchTimeout`). Throws when the read finds
    /// iCloud can't be reached, so no `share(_:to:)` is made offline; any
    /// other failure falls back to the store's copy, as `current` does.
    /// `current` keeps CloudKit's default timeouts: Manage Sharing uses it,
    /// and falling back there more often risks saving a stale change tag.
    @concurrent
    static func latestForAttach(_ share: CKShare, container: NSPersistentCloudKitContainer) async throws -> CKShare {
        let cloud = await CloudKitConfigurationService.container
        let database = share.recordID.zoneID.ownerName == CKCurrentUserDefaultName
            ? cloud.privateCloudDatabase
            : cloud.sharedCloudDatabase
        let configuration = CKOperation.Configuration()
        configuration.timeoutIntervalForRequest = attachFetchTimeout.request
        configuration.timeoutIntervalForResource = attachFetchTimeout.resource
        let id = share.recordID
        let fetched: Result<CKRecord, any Error>?
        do {
            // `records(for:)`, which Apple documents inside `configuredWith`;
            // whether `record(for:)` honors the configuration isn't said.
            fetched = try await database.configuredWith(configuration: configuration) { configured in
                try await configured.records(for: [id])[id]
            }
        } catch {
            fetched = .failure(error)
        }
        switch fetched {
        case .some(.success(let record as CKShare)):
            return record
        case .some(.failure(let error)) where indicatesNoConnection(error as NSError):
            throw error
        default:
            let stored = (try? container.fetchShares(in: nil)) ?? []
            return stored.first { $0.recordID == id } ?? share
        }
    }

    /// Why a failure should end the whole pass: every later call would fail
    /// the same way. A plain phrase that finishes "…couldn't be added
    /// because …"; the error's domain and code are logged where it's caught.
    /// A network failure used to send the rest of a chunk one record at a
    /// time, each waiting on the network in turn, so a weak link held a pass
    /// (and every mark tapped meanwhile) for minutes.
    static func stopReason(for error: NSError) -> String? {
        if indicatesDeadMirroringDelegate(error) {
            return "iCloud stopped syncing"
        }
        if error.domain == NSCocoaErrorDomain, error.code == shareTimedOutCode {
            return "iCloud took too long to answer"
        }
        if indicatesNoConnection(error) {
            return "iCloud couldn't be reached"
        }
        if indicatesServerBusy(error) {
            return "iCloud is busy"
        }
        return nil
    }

    /// Core Data's "timed out" for a share export: on a weak link, the
    /// likeliest way a `share(_:to:)` ends.
    static let shareTimedOutCode = 134060

    /// CloudKit's "no network" codes. `serverResponseLost` may mean the
    /// server did it, which is safe to try again: every call first drops
    /// what's already shared (`stillOutside`).
    private static let noConnectionCodes: Set<Int> = [
        CKError.Code.networkUnavailable.rawValue,
        CKError.Code.networkFailure.rawValue,
        CKError.Code.serverResponseLost.rawValue
    ]

    /// CloudKit's "not now" codes, which may say how long to wait.
    private static let serverBusyCodes: Set<Int> = [
        CKError.Code.serviceUnavailable.rawValue,
        CKError.Code.requestRateLimited.rawValue,
        CKError.Code.zoneBusy.rawValue
    ]

    /// True when `error`, or one wrapped inside it, says iCloud couldn't be
    /// reached: CloudKit's network codes, any URL-loading error, or Core
    /// Data's share-export timeout.
    static func indicatesNoConnection(_ error: NSError) -> Bool {
        errorChain(of: error).contains { leaf in
            switch leaf.domain {
            case NSURLErrorDomain: true
            case CKErrorDomain: noConnectionCodes.contains(leaf.code)
            case NSCocoaErrorDomain: leaf.code == shareTimedOutCode
            default: false
            }
        }
    }

    /// True when `error`, or one wrapped inside it, says CloudKit is busy or
    /// throttling.
    static func indicatesServerBusy(_ error: NSError) -> Bool {
        errorChain(of: error).contains { $0.domain == CKErrorDomain && serverBusyCodes.contains($0.code) }
    }

    /// The longest wait CloudKit asked for anywhere in `error`, if any. Read
    /// for every code: Apple's pages disagree on which carry it.
    static func retryAfter(in error: NSError) -> TimeInterval? {
        errorChain(of: error)
            .compactMap { ($0.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue }
            .max()
    }

    /// `error` and every error wrapped inside it: underlying errors, and a
    /// partial failure's per-record errors.
    private static func errorChain(of error: NSError, depth: Int = 0) -> [NSError] {
        guard depth < 4 else { return [error] }
        let info = error.userInfo
        var inner: [NSError] = []
        if let underlying = info[NSUnderlyingErrorKey] as? NSError { inner.append(underlying) }
        if let many = info[NSMultipleUnderlyingErrorsKey] as? [NSError] { inner += many }
        if let partial = info[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error] {
            inner += partial.values.map { $0 as NSError }
        }
        return [error] + inner.flatMap { errorChain(of: $0, depth: depth + 1) }
    }

    /// True when `error` is CloudKit mirroring's "delegate never initialized"
    /// family. Once this appears, every later `container.share(_:to:)` fails
    /// the same way — by raising an Objective-C exception inside a fault,
    /// which no Swift `catch` can trap — so the only safe move is to stop.
    ///
    /// - `134406` — request aborted; the mirroring delegate never initialized.
    /// - `134421` — export hit an unhandled exception analyzing history.
    /// - `256` on the store file — the sqlite file can no longer be opened.
    static func indicatesDeadMirroringDelegate(_ error: NSError) -> Bool {
        let deadDelegateCodes: Set<Int> = [134406, 134421, NSFileReadUnknownError]
        if error.domain == NSCocoaErrorDomain, deadDelegateCodes.contains(error.code) {
            return true
        }
        return error.localizedDescription.range(of: "never successfully initialized", options: .caseInsensitive) != nil
    }

    /// `container.share(objects, to: share)` on a background context, off the
    /// main actor. The faults are fired with `existingObject(with:)` first:
    /// `object(with:)` hands back an unfired fault, and a fault that fails
    /// inside `container.share` raises an uncatchable Objective-C exception;
    /// fired here, the same failure is a Swift error the caller can handle.
    static func shareOffMain(
        _ ids: [NSManagedObjectID],
        to share: CKShare,
        container: NSPersistentCloudKitContainer
    ) async throws {
        try await Task.detached {
            let context = container.newBackgroundContext()
            let objects: [NSManagedObject] = try context.performAndWait {
                try ids.map { try context.existingObject(with: $0) }
            }
            _ = try await container.share(objects, to: share)
        }.value
    }

    /// `container.persistUpdatedShare(share, in:)` for the store with
    /// `storeIdentifier`, off the main actor. It blocks its thread on the
    /// same `__ulock_wait` as `share(_:to:)` until the share's export
    /// resolves: called from the main actor, removing a participant froze
    /// the Mac's Manage Sharing window with a spinner (2026-09-29).
    static func persistUpdatedShareOffMain(
        _ share: CKShare,
        storeIdentifier: String,
        container: NSPersistentCloudKitContainer
    ) async throws -> CKShare {
        try await Task.detached {
            let stores = container.persistentStoreCoordinator.persistentStores
            guard let store = stores.first(where: { $0.identifier == storeIdentifier }) else {
                throw CocoaError(.persistentStoreOperation)
            }
            return try await container.persistUpdatedShare(share, in: store)
        }.value
    }

    /// Creates the classroom share, seeded with `seedID`, off the main actor.
    static func createShareOffMain(
        seedID: NSManagedObjectID,
        container: NSPersistentCloudKitContainer
    ) async throws -> CKShare {
        try await Task.detached {
            let context = container.newBackgroundContext()
            let seed: NSManagedObject = try context.performAndWait {
                try context.existingObject(with: seedID)
            }
            let (_, share, _) = try await container.share([seed], to: nil)
            return share
        }.value
    }
}
