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
    static func existing(_ ids: [CKRecord.ID], in database: CKDatabase) async throws -> [CKRecord.ID: Date] {
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
