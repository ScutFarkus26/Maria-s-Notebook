// BackupImporter+RecordIDs.swift
// The record IDs a backup holds, for checking it before a run deletes records.

import Foundation

nonisolated extension BackupImporter {

    /// The `id` of every row of `entityNames` in the archive, read as a restore reads them:
    /// each row decoded with its entity's full DTO type (`visitRows`), so an entry the
    /// restore would skip holds no IDs here, and a later entry of the same name replaces an
    /// earlier one. Other entities' rows aren't decoded. One entry's bytes are in memory at
    /// a time. `@concurrent`: runs off the main actor.
    @concurrent
    static func recordIDs(at url: URL, of entityNames: Set<String>) async throws -> [String: Set<UUID>] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var ids: [String: Set<UUID>] = [:]
        _ = try BackupReader.streamEntities(
            from: url,
            keyProvider: { try BackupEncryptionKeyStore.requireKey() },
            body: { entry in
                guard entityNames.contains(entry.entityName) else { return }
                var rows = Set<UUID>()
                let skipped = visitRows(of: entry, using: decoder) { row in
                    if let id = (row as? any BackupRowDTO)?.id { rows.insert(id) }
                }
                if skipped == nil { ids[entry.entityName] = rows }
            }
        )
        return ids
    }
}
