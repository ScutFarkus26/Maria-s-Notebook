// BackupImporter+Preview.swift
// Reads a backup for the restore preview without keeping its records.

import Foundation

nonisolated extension BackupImporter {

    /// What `BackupCoordinator.previewImport` needs from an archive.
    struct DecodedPreview: Sendable {
        let manifest: BackupArchiveManifest
        let digest: BackupPreviewDigest
        /// The same warnings a restore of this file would add (`restore(from:into:…)`).
        let warnings: [String]
    }

    /// Streams the archive one entity entry at a time and decodes every row
    /// exactly as a restore decodes it — with the entity's full DTO type,
    /// through `visitRows`, so an entry the restore would skip is skipped here
    /// with the same warning — but keeps only each row's ID and the entry's
    /// row count. One entry's bytes and one record are in memory at a time.
    /// The old preview decoded the whole archive (every entry's bytes, then
    /// every record) to answer the same questions. `@concurrent`: runs off the
    /// main actor.
    @concurrent
    static func decodePreview(at url: URL) async throws -> DecodedPreview {
        BackupPipelineProbe.reach("decode preview")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var digest = BackupPreviewDigest()
        var warnings: [String] = []

        let manifest = try BackupReader.streamEntities(
            from: url,
            keyProvider: { try BackupEncryptionKeyStore.requireKey() },
            body: { entry in
                var rows = BackupPreviewDigest.EntityRows(entityName: entry.entityName)
                if let warning = visitRows(of: entry, using: decoder, { rows.add($0) }) {
                    // Skipped, as the restore skips it: nothing of it counts.
                    warnings.append(warning)
                } else {
                    digest.record(rows)
                }
            }
        )
        return DecodedPreview(manifest: manifest, digest: digest, warnings: warnings)
    }
}
