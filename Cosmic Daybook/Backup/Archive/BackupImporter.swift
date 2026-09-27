// BackupImporter.swift
// Restores a v17+ backup file into Core Data.
//
// `restore(from:into:…)` is the app's restore and the checkpoint rollback's:
// `decodeArchive` reads, decrypts and decodes the archive off the main actor,
// each entry decoded as it is read, into one `BackupPayload`; then
// `BackupService.importRows` — the one import path, which the tests'
// hand-built payloads share through `importPayload` — imports it one entity
// type at a time, moving each type out of the payload and freeing it once
// imported. The entity-import dispatch, the replace-mode clear, the
// denormalized-field repair and the CloudKit-sync wait all live there.
//
// Any entry that fails to decode is skipped with a warning that propagates
// into the operation summary the user sees — never silently.

import Foundation
import CoreData
import OSLog

enum BackupImporter {
    // nonisolated so the off-main decode path (reconstructPayload) can log.
    private nonisolated static let logger = Logger.backup

    /// A whole archive decoded at once, produced off-main by
    /// `decodeArchive(at:)`.
    struct DecodedArchive: Sendable {
        let manifest: BackupArchiveManifest
        let payload: BackupPayload
        let warnings: [String]
        let encrypted: Bool
    }

    // MARK: - Public API

    /// Reads, decrypts, and JSON-decodes the archive into one typed payload,
    /// decoding each entry as it is read — every entry through `decode`, in
    /// archive order, so the payload and warnings are exactly
    /// `reconstructPayload`'s — so no entry's NDJSON outlives its decode.
    /// (Until 2026-09-27 every entry was read before any was decoded, so all
    /// of the archive's NDJSON and all of its records were alive together.)
    /// Fails as `BackupReader.read` does. `@concurrent` so it runs off the
    /// main actor (a plain `nonisolated async` function runs on its caller's
    /// actor); only the Core Data import that follows needs the main actor.
    @concurrent
    nonisolated static func decodeArchive(at url: URL) async throws -> DecodedArchive {
        BackupPipelineProbe.reach("decode")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var payload = BackupPayload.collecting(preferences: PreferencesDTO(values: [:]))
        var warnings: [String] = []
        let backup = try BackupReader.streamBackup(
            from: url,
            keyProvider: { try BackupEncryptionKeyStore.requireKey() },
            entity: { entry in
                autoreleasepool {
                    if let warning = decode(entry, into: &payload, using: decoder) {
                        warnings.append(warning)
                    }
                }
            }
        )
        payload.preferences = backup.preferences ?? PreferencesDTO(values: [:])
        return DecodedArchive(
            manifest: backup.manifest,
            payload: payload,
            warnings: warnings,
            encrypted: BackupArchive.isEncryptedArchive(at: url)
        )
    }

    /// Restores the backup at `url` into `viewContext`: decoded off the main
    /// actor, then imported on it in one turn, one entity type at a time (see
    /// `BackupService.importRows`). The payload is handed over whole to the
    /// source, which holds its only copy and gives each type up as it is
    /// imported, so the records never exist twice and shrink as the import
    /// goes. Warnings about entries left out — rows that do not decode, an
    /// entity this version does not know — follow the import's own, in
    /// archive order.
    static func restore(
        from url: URL,
        into viewContext: NSManagedObjectContext,
        mode: BackupService.RestoreMode,
        appRouter: AppRouter,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        let (source, warnings) = try await decodedSource(at: url)

        progress(0.35, "Importing\u{2026}")
        let summary = try await BackupService().importRows(
            from: source,
            viewContext: viewContext,
            mode: mode,
            appRouter: appRouter,
            progress: progress
        )
        return warnings.isEmpty ? summary : summary.appending(warnings: warnings)
    }

    /// The archive decoded into a source holding the payload's only copy:
    /// `decoded` goes when this returns, before the import starts.
    private static func decodedSource(at url: URL) async throws -> (BackupPayloadSource, [String]) {
        let decoded = try await decodeArchive(at: url)
        let envelope = BackupEnvelope(
            formatVersion: decoded.manifest.formatVersion,
            encrypted: decoded.encrypted,
            createdAt: decoded.manifest.createdAt,
            fileName: url.lastPathComponent,
            entityCounts: decoded.manifest.entityCounts
        )
        return (BackupPayloadSource(decoded.payload, envelope: envelope), decoded.warnings)
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
