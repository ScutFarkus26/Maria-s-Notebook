import CloudKit
import Foundation
import Synchronization

/// Asks the CloudKit server directly what it holds, rather than trusting what the local
/// mirroring says it sent. `ClassroomShareRelease` deletes a shared record only after this
/// finds its private copy on the server, and counts itself finished only once this no
/// longer finds the shared original.
nonisolated enum CloudKitServerCheck {
    /// CloudKit takes at most 400 records per fetch.
    static let batchSize = 400

    /// A request that hasn't answered in this long is abandoned and counts as transient.
    static let requestTimeout: Duration = .seconds(90)

    struct TimedOut: LocalizedError {
        var errorDescription: String? { "iCloud didn't answer in time" }
    }

    /// The server said the zone some of the records were in doesn't exist (a share that was
    /// stopped, say). Not transient. Only a wait for records to be gone reads it as their
    /// being gone (`ClassroomShareRelease.waitForGone`, bug hunt 2026-11-02 #41); anywhere
    /// else it stops the run, so a missing zone is never taken for a record deleted on
    /// another device, whose private copy would then go too.
    struct ZoneMissing: LocalizedError {
        /// What the server does hold of the records asked about.
        let found: [CKRecord.ID: Date]
        /// The records whose zone is gone.
        let inMissingZones: Set<CKRecord.ID>
        var errorDescription: String? { "iCloud says the zone of \(inMissingZones.count) record(s) is gone" }
    }

    /// Errors worth asking again for: the network, throttling, a busy zone, a slow answer.
    static func isTransient(_ error: Error) -> Bool {
        if error is TimedOut { return true }
        guard let error = error as? CKError else { return false }
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }

    /// `operation`, abandoned with `TimedOut` after `limit`: a CloudKit request can sit in
    /// the system's queue indefinitely, and a caller polling with a deadline must not hang.
    /// The answer, the limit or the caller's cancellation, whichever comes first, ends the
    /// wait (`TimeoutRace`): an operation that doesn't stop when cancelled (reading the
    /// mirroring metadata off the main actor doesn't) is left to finish on its own, its
    /// answer dropped. A task group would wait for it.
    static func withTimeout<T: Sendable>(
        _ limit: Duration = requestTimeout,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let race = TimeoutRace<T>()
        let work = Task {
            do {
                race.finish(.success(try await operation()))
            } catch {
                race.finish(.failure(error))
            }
        }
        let timer = Task {
            guard (try? await Task.sleep(for: limit)) != nil else { return }
            race.finish(.failure(TimedOut()))
        }
        defer {
            timer.cancel()
            work.cancel()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { race.wait($0) }
        } onCancel: {
            race.finish(.failure(CancellationError()))
        }
    }

    /// Of `ids`, the records the server holds, with their modification dates. A record the
    /// server says doesn't exist is left out. Records whose zone is gone throw `ZoneMissing`,
    /// holding the rest's answer; any other failure throws, so a network problem is never
    /// read as "gone".
    static func existing(_ ids: [CKRecord.ID], in database: CKDatabase) async throws -> [CKRecord.ID: Date] {
        try await withTimeout { try await fetchExisting(ids, in: database) }
    }

    private static func fetchExisting(
        _ ids: [CKRecord.ID], in database: CKDatabase
    ) async throws -> [CKRecord.ID: Date] {
        var found: [CKRecord.ID: Date] = [:]
        var inMissingZones = Set<CKRecord.ID>()
        for start in stride(from: 0, to: ids.count, by: batchSize) {
            let batch = Array(ids[start..<min(start + batchSize, ids.count)])
            let answer = try sorted(try await database.records(for: batch, desiredKeys: []))
            found.merge(answer.found) { $1 }
            inMissingZones.formUnion(answer.inMissingZones)
        }
        if !inMissingZones.isEmpty { throw ZoneMissing(found: found, inMissingZones: inMissingZones) }
        return found
    }

    /// The server's answer for each record of one fetch: the records it holds, with their
    /// dates, and the ones whose zone is gone. One it says doesn't exist is in neither; any
    /// other failure throws.
    static func sorted(
        _ results: [CKRecord.ID: Result<CKRecord, any Error>]
    ) throws -> (found: [CKRecord.ID: Date], inMissingZones: Set<CKRecord.ID>) {
        var found: [CKRecord.ID: Date] = [:]
        var inMissingZones = Set<CKRecord.ID>()
        for (id, result) in results {
            switch result {
            case .success(let record):
                found[id] = record.modificationDate ?? .distantPast
            case .failure(let error as CKError) where error.code == .unknownItem:
                continue
            case .failure(let error as CKError) where error.code == .zoneNotFound || error.code == .userDeletedZone:
                inMissingZones.insert(id)
            case .failure(let error):
                throw error
            }
        }
        return (found, inMissingZones)
    }

    /// How many records of each type the zone holds on the server ("CD_Student": 24, …),
    /// read through the zone's full change list. For the report after a release.
    static func recordTypeCounts(inZone zoneName: String, database: CKDatabase) async throws -> [String: Int] {
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        var counts: [String: Int] = [:]
        var token: CKServerChangeToken?
        var moreComing = true
        while moreComing {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token, desiredKeys: [])
            for result in changes.modificationResultsByID.values {
                if case .success(let modification) = result {
                    counts[modification.record.recordType, default: 0] += 1
                }
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }
        return counts
    }
}

/// One request racing its time limit (`CloudKitServerCheck.withTimeout`): the first of its
/// answer, the limit or a cancellation resumes the caller, once; the others are dropped.
nonisolated private final class TimeoutRace<T: Sendable>: Sendable {
    private enum State {
        /// Nothing has finished, and the caller isn't waiting yet.
        case started
        /// The caller waits here.
        case waiting(CheckedContinuation<T, any Error>)
        /// Finished before the caller began to wait.
        case finished(Result<T, any Error>)
        /// The caller has its answer.
        case resumed
    }

    private let state = Mutex<State>(.started)

    /// The caller begins to wait; at once, if the race is already over.
    func wait(_ continuation: CheckedContinuation<T, any Error>) {
        let early: Result<T, any Error>? = state.withLock { state in
            guard case .finished(let result) = state else {
                state = .waiting(continuation)
                return nil
            }
            state = .resumed
            return result
        }
        if let early { continuation.resume(with: early) }
    }

    /// Ends the race with `result`, unless it's over.
    func finish(_ result: Result<T, any Error>) {
        let waiting: CheckedContinuation<T, any Error>? = state.withLock { state in
            switch state {
            case .started:
                state = .finished(result)
                return nil
            case .waiting(let continuation):
                state = .resumed
                return continuation
            case .finished, .resumed:
                return nil
            }
        }
        waiting?.resume(with: result)
    }
}
