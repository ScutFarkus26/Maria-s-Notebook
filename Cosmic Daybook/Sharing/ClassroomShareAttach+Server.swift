import Foundation
@preconcurrency import CoreData
import CloudKit

// What the server says: the share's latest copy before each attach call, and
// why a call failed (which failures end a pass, which mean iCloud couldn't be
// reached, so the Daybook Assistant rests briefly and says so, and how long
// CloudKit asked to wait). Compiled by both apps, like `ClassroomShareAttach.swift`.

nonisolated extension ClassroomShareAttach {

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
}
