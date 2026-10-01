import CloudKit
import Foundation

/// Asks the CloudKit server directly what it holds, rather than trusting what the local
/// mirroring says it sent. `ClassroomShareRelease` deletes a shared record only after this
/// finds its private copy on the server, and counts itself finished only once this no
/// longer finds the shared original.
nonisolated enum CloudKitServerCheck {
    /// CloudKit takes at most 400 records per fetch.
    static let batchSize = 400

    /// Of `ids`, the records the server holds, with their modification dates. A record the
    /// server says doesn't exist is left out; any other failure throws, so a network problem
    /// is never read as "gone".
    /// A request that hasn't answered in this long is abandoned and counts as transient.
    static let requestTimeout: Duration = .seconds(90)

    struct TimedOut: LocalizedError {
        var errorDescription: String? { "iCloud didn't answer in time" }
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
    static func withTimeout<T: Sendable>(
        _ limit: Duration = requestTimeout,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }

    static func existing(_ ids: [CKRecord.ID], in database: CKDatabase) async throws -> [CKRecord.ID: Date] {
        try await withTimeout { try await fetchExisting(ids, in: database) }
    }

    private static func fetchExisting(
        _ ids: [CKRecord.ID], in database: CKDatabase
    ) async throws -> [CKRecord.ID: Date] {
        var found: [CKRecord.ID: Date] = [:]
        for start in stride(from: 0, to: ids.count, by: batchSize) {
            let batch = Array(ids[start..<min(start + batchSize, ids.count)])
            let results = try await database.records(for: batch, desiredKeys: [])
            for (id, result) in results {
                switch result {
                case .success(let record):
                    found[id] = record.modificationDate ?? .distantPast
                case .failure(let error as CKError) where error.code == .unknownItem:
                    continue
                case .failure(let error):
                    throw error
                }
            }
        }
        return found
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
