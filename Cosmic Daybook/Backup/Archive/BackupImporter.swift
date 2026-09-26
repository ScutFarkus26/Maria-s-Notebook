// BackupImporter.swift
// Imports a decoded v17+ backup into Core Data.
//
// The strategy: reconstruct a `BackupPayload` struct from the decoded NDJSON
// entries (off the main actor — it's pure JSON decoding), then hand it to
// `BackupService.importPayload(...)` — the single shared post-decode import
// path used by the current import flow and the internal checkpoint restore
// path. This way the entity-import dispatch, deleteAll-for-replace,
// denormalized field repair, and CloudKit-sync wait all live in one place.
//
// Any entity type that fails to decode is skipped with a warning that
// propagates into the operation summary the user sees — never silently.

import Foundation
import CoreData
import OSLog

enum BackupImporter {
    // nonisolated so the off-main decode path (reconstructPayload) can log.
    private nonisolated static let logger = Logger.backup

    /// Everything needed to import or preview a backup, produced off-main by
    /// `decodeArchive(at:)`.
    struct DecodedArchive: Sendable {
        let manifest: BackupArchiveManifest
        let payload: BackupPayload
        let warnings: [String]
        let encrypted: Bool
    }

    // MARK: - Public API

    /// Reads, decrypts, and JSON-decodes the archive into a typed payload.
    /// `@concurrent` so the whole decode pipeline runs off the main actor
    /// (a plain `nonisolated async` function runs on its caller's actor, and
    /// every caller is main-actor code); only the Core Data import that
    /// follows needs the main actor.
    @concurrent
    nonisolated static func decodeArchive(at url: URL) async throws -> DecodedArchive {
        BackupPipelineProbe.reach("decode")
        let decoded = try BackupReader.read(from: url)
        let (payload, warnings) = reconstructPayload(from: decoded)
        return DecodedArchive(
            manifest: decoded.manifest,
            payload: payload,
            warnings: warnings,
            encrypted: BackupArchive.isEncryptedArchive(at: url)
        )
    }

    /// Imports a decoded backup into the given Core Data context.
    /// Mode handling (merge/replace), deleteAll, save, CloudKit-sync-wait, and
    /// the operation summary are all owned by the underlying `importPayload`.
    /// Decode-time warnings are appended to the summary so partial decodes
    /// are visible in the UI, not just the log.
    static func importDecoded(
        _ archive: DecodedArchive,
        from fileURL: URL,
        into viewContext: NSManagedObjectContext,
        mode: BackupService.RestoreMode,
        appRouter: AppRouter,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {

        progress(0.35, "Importing\u{2026}")
        let service = BackupService()
        let summary = try await service.importPayload(
            payload: archive.payload,
            envelope: BackupEnvelope(
                formatVersion: archive.manifest.formatVersion,
                encrypted: archive.encrypted,
                createdAt: archive.manifest.createdAt,
                fileName: fileURL.lastPathComponent,
                entityCounts: archive.manifest.entityCounts
            ),
            viewContext: viewContext,
            mode: mode,
            appRouter: appRouter,
            progress: progress
        )
        return archive.warnings.isEmpty ? summary : summary.appending(warnings: archive.warnings)
    }

    // MARK: - Payload Reconstruction

    /// Walks the decoded entries and decodes each one into its typed DTO
    /// array, assigning into the corresponding `BackupPayload` field.
    ///
    /// A malformed entry skips that entity type but the skip is returned as a
    /// warning for the operation summary. Unrecognized entity names are also
    /// surfaced (forward-compat: a backup made by a future app version
    /// partially imports rather than fails, but the user learns what was
    /// left behind).
    nonisolated static func reconstructPayload(
        from decoded: BackupReader.DecodedBackup
    ) -> (payload: BackupPayload, warnings: [String]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Initialize with empty arrays; we fill the ones we have entries for.
        var payload = BackupPayload.collecting(
            preferences: decoded.preferences ?? PreferencesDTO(values: [:])
        )

        var warnings: [String] = []
        for entry in decoded.entries {
            if let warning = decode(entry, into: &payload, using: decoder) {
                warnings.append(warning)
            }
        }

        return (payload, warnings)
    }

    /// Decodes one entity entry into its `BackupPayload` field, every row with
    /// that entity's DTO type. Returns the warning to surface when the entry is
    /// skipped — an entity this version does not know, or a row that does not
    /// decode (then the field keeps what it held) — and nil when it decoded.
    nonisolated static func decode(
        _ entry: BackupEntityEntry,
        into payload: inout BackupPayload,
        using decoder: JSONDecoder
    ) -> String? {
        guard let entityDecoder = entityDecoders[entry.entityName] else {
            return unknownEntityWarning(entry.entityName)
        }
        do {
            try entityDecoder.assign(&payload, BackupReader.ndjsonLines(in: entry), decoder)
            return nil
        } catch {
            return unreadableEntryWarning(entry.entityName, error)
        }
    }

    /// Decodes one entity entry's rows exactly as `decode(_:into:using:)`
    /// does, but hands each row to `visit` and keeps none of them — the
    /// preview's way to count and collect IDs with one record in memory at a
    /// time. Returns the same warning `decode` would, and nil when every row
    /// decoded; after a warning, `visit` may have seen some rows.
    nonisolated static func visitRows(
        of entry: BackupEntityEntry,
        using decoder: JSONDecoder,
        _ visit: (any Sendable) -> Void
    ) -> String? {
        guard let entityDecoder = entityDecoders[entry.entityName] else {
            return unknownEntityWarning(entry.entityName)
        }
        do {
            try entityDecoder.visit(BackupReader.ndjsonLines(in: entry), decoder, visit)
            return nil
        } catch {
            return unreadableEntryWarning(entry.entityName, error)
        }
    }

    private nonisolated static func unknownEntityWarning(_ entityName: String) -> String {
        let message = "Unknown entity '\(entityName)' in backup \u{2014} skipped " +
            "(likely created by a newer app version)."
        logger.warning("\(message, privacy: .public)")
        return message
    }

    private nonisolated static func unreadableEntryWarning(_ entityName: String, _ error: Error) -> String {
        let message = "\(entityName) records could not be read from this backup " +
            "and were skipped: \(error.localizedDescription)"
        logger.warning("\(message, privacy: .public)")
        return message
    }

    // MARK: - Per-Entity Dispatch

    /// Every entity name this importer can decode. The coverage tests compare
    /// this against `BackupEntityRegistry` and `BackupWriter`.
    nonisolated static var handledEntityNames: [String] {
        Array(entityDecoders.keys)
    }
}
