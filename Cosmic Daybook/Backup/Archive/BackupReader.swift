// BackupReader.swift
// Decodes a v17+ backup file into a manifest + ordered entries.
//
// Reads encrypted v19 archives ("AA01") and plain v17/v18 archives ("pbz*").
// The legacy v5–v16 JSON-envelope decoder no longer exists anywhere in the
// app; pre-v17 files cannot be read (see the external recovery recipe in the
// project docs if one ever needs to be recovered).

import Foundation
import CryptoKit
import OSLog

nonisolated public enum BackupReader {
    private static let logger = Logger.backup

    public struct DecodedBackup: Sendable {
        public let manifest: BackupArchiveManifest
        public let entries: [BackupEntityEntry]
        public let preferences: PreferencesDTO?
    }

    /// Result of a structural verification pass: the decoded manifest plus
    /// the actual NDJSON row count found in each entity entry. Streaming —
    /// entry bodies are counted and discarded, never accumulated.
    public struct StructureVerification: Sendable {
        public let manifest: BackupArchiveManifest
        public let entryLineCounts: [String: Int]
        /// How many `photos/` entries the archive holds (v28+).
        public let photoCount: Int
    }

    public enum ReadError: LocalizedError {
        case notArchiveFormat
        case manifestMissing
        case manifestMalformed(reason: String)
        case unsupportedFormatVersion(found: Int, supported: ClosedRange<Int>)
        case entryPathInvalid(String)

        /// What the guide reads. The format version, the manifest's fault and
        /// the entry path go to the log where the error is caught.
        public var errorDescription: String? {
            switch self {
            case .notArchiveFormat:
                return Self.notOurs
            case .manifestMissing, .manifestMalformed, .entryPathInvalid:
                return BackupArchive.ArchiveError.damaged
            case .unsupportedFormatVersion(let found, let supported):
                return found > supported.upperBound
                    ? "This backup was made by a newer version of Cosmic Daybook. Update the app, then try again."
                    : Self.notOurs
            }
        }

        private static let notOurs =
            "This file isn't a Cosmic Daybook backup, or it's from a much older version of the app."
    }

    /// Supported format range. Bump the upper bound when we add a new format
    /// version (and keep the reader backward-compatible for the lower bound).
    /// v20 adds Guardian/ParentCommunication entries; v19 wraps the same
    /// entries in an encrypted AEA container; v18 added Stories/Book Club/
    /// Year Plan/Day Pad entries; v17/v18 files still read (plain compressed
    /// container, new entries simply absent). v28 adds `photos/<filename>`
    /// entries (`BackupPhotos`), which a v27 reader would reject as an
    /// unexpected path — hence the version. v29 adds `note` to attendance
    /// entries; v30 attendance day locks; v31 supply transactions; v32 `markedAt`
    /// on attendance entries; v33 `leftAt` on attendance entries; v34 the
    /// front-desk attendance emails and their settings; v35 `leavesAt` on
    /// attendance entries; v36 `returnedAt` and `statusBeforeLeavingRaw` on
    /// attendance entries.
    public static let supportedFormatVersions: ClosedRange<Int> = 17...36

    // MARK: - Public API

    /// Reads a backup file fully into memory using the app's Keychain key for
    /// encrypted archives. Returns the manifest, preferences (if present),
    /// and one entry per non-empty entity NDJSON payload.
    public static func read(from url: URL) throws -> DecodedBackup {
        try read(from: url) { try BackupEncryptionKeyStore.requireKey() }
    }

    /// As `read(from:)`, with an injectable key provider (only invoked for
    /// encrypted archives — plain v17/v18 files never touch the Keychain).
    public static func read(
        from url: URL,
        keyProvider: () throws -> SymmetricKey
    ) throws -> DecodedBackup {
        var entries: [BackupEntityEntry] = []
        let backup = try streamBackup(from: url, keyProvider: keyProvider) { entries.append($0) }

        let readerMsg = "BackupReader decoded v\(backup.manifest.formatVersion) backup " +
            "with \(entries.count) entity entries"
        logger.info("\(readerMsg, privacy: .public)")
        return DecodedBackup(manifest: backup.manifest, entries: entries, preferences: backup.preferences)
    }

    /// Streams a backup file entry by entry, as `streamEntities` does, and
    /// decodes its preferences entry as `read(from:)` does: nil when there is
    /// none or it does not decode (logged; the restore then keeps the current
    /// settings). The restore reads an archive this way, holding one entity's
    /// bytes at a time. `photo` receives each note photo entry's filename and
    /// bytes (v28+).
    public static func streamBackup(
        from url: URL,
        keyProvider: () throws -> SymmetricKey,
        entity: (BackupEntityEntry) throws -> Void,
        photo: (String, Data) throws -> Void = { _, _ in }
    ) throws -> (manifest: BackupArchiveManifest, preferences: PreferencesDTO?) {
        var decodedPreferences: PreferencesDTO?
        let manifest = try walk(
            url,
            keyProvider: keyProvider,
            preferences: { data in
                do {
                    decodedPreferences = try decodePreferences(from: data)
                } catch {
                    let msg = "Backup preferences entry failed to decode; " +
                        "restore will keep current settings: \(error.localizedDescription)"
                    logger.warning("\(msg, privacy: .public)")
                }
            },
            entity: entity,
            photo: photo
        )
        return (manifest, decodedPreferences)
    }

    /// Streams a backup file entry by entry: `body` sees each entity entry as
    /// it is decrypted, and nothing keeps the entry once `body` returns, so
    /// only one entity's bytes are in memory at a time. The preferences entry
    /// is skipped. Validates exactly as `read(from:)` does: each entry's path
    /// as it arrives, then that a manifest was present and its format version
    /// is supported. Returns the manifest.
    public static func streamEntities(
        from url: URL,
        keyProvider: () throws -> SymmetricKey,
        body: (BackupEntityEntry) throws -> Void
    ) throws -> BackupArchiveManifest {
        try walk(url, keyProvider: keyProvider, preferences: { _ in }, entity: body)
    }

    /// The one pass over an archive that `read` and `streamEntities` share:
    /// manifest decoded (a malformed one throws at once), preferences handed
    /// over raw, entity entries parsed and handed over in archive order, photo
    /// entries handed to `photo` (ignored by default), then the manifest's
    /// presence and format version checked.
    private static func walk(
        _ url: URL,
        keyProvider: () throws -> SymmetricKey,
        preferences: (Data) -> Void,
        entity: (BackupEntityEntry) throws -> Void,
        photo: (String, Data) throws -> Void = { _, _ in }
    ) throws -> BackupArchiveManifest {
        guard BackupArchive.isBackupArchive(at: url) else {
            throw ReadError.notArchiveFormat
        }

        var manifest: BackupArchiveManifest?
        try BackupArchive.read(from: url, encryptionKey: keyProvider) { path, data in
            switch path {
            case "manifest.json":
                manifest = try decodeManifest(from: data)
            case "preferences.json":
                preferences(data)
            default:
                if let name = try BackupPhotos.filename(fromArchivePath: path) {
                    try photo(name, data)
                } else if let entry = try parseEntityEntry(path: path, ndjson: data) {
                    try entity(entry)
                }
            }
            return true
        }

        guard let manifest else { throw ReadError.manifestMissing }
        guard supportedFormatVersions.contains(manifest.formatVersion) else {
            throw ReadError.unsupportedFormatVersion(
                found: manifest.formatVersion,
                supported: supportedFormatVersions
            )
        }
        return manifest
    }

    /// Streams the whole archive, decoding only the manifest and counting the
    /// NDJSON rows in each entity entry. This validates container integrity
    /// (full decrypt/decompress pass) and per-entity record counts without
    /// JSON-decoding every row or holding entry bodies in memory.
    ///
    /// Used by `BackupVerification` for user-initiated checks (uses the app's
    /// Keychain key for encrypted archives).
    public static func verifyStructure(at url: URL) throws -> StructureVerification {
        try verifyStructure(at: url) { try BackupEncryptionKeyStore.requireKey() }
    }

    /// As `verifyStructure(at:)`, with an injectable key provider. Used by
    /// `BackupWriter` for post-write verification.
    public static func verifyStructure(
        at url: URL,
        keyProvider: () throws -> SymmetricKey
    ) throws -> StructureVerification {
        guard BackupArchive.isBackupArchive(at: url) else {
            throw ReadError.notArchiveFormat
        }

        var manifest: BackupArchiveManifest?
        var lineCounts: [String: Int] = [:]
        var photoCount = 0

        try BackupArchive.read(from: url, encryptionKey: keyProvider) { path, data in
            switch path {
            case "manifest.json":
                manifest = try decodeManifest(from: data)
            case "preferences.json":
                break
            default:
                if try BackupPhotos.filename(fromArchivePath: path) != nil {
                    photoCount += 1
                } else if let entry = try parseEntityEntry(path: path, ndjson: data) {
                    lineCounts[entry.entityName] = entry.count
                }
            }
            return true
        }

        guard let manifest else { throw ReadError.manifestMissing }
        guard supportedFormatVersions.contains(manifest.formatVersion) else {
            throw ReadError.unsupportedFormatVersion(
                found: manifest.formatVersion,
                supported: supportedFormatVersions
            )
        }
        return StructureVerification(manifest: manifest, entryLineCounts: lineCounts, photoCount: photoCount)
    }

    // MARK: - Decode Helpers

    private static func decodeManifest(from data: Data) throws -> BackupArchiveManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupArchiveManifest.self, from: data)
        } catch {
            throw ReadError.manifestMalformed(reason: error.localizedDescription)
        }
    }

    private static func decodePreferences(from data: Data) throws -> PreferencesDTO {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PreferencesDTO.self, from: data)
    }

    private static func parseEntityEntry(
        path: String,
        ndjson: Data
    ) throws -> BackupEntityEntry? {
        // Expected: "<store>/<EntityName>.ndjson"
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2,
              parts[1].hasSuffix(".ndjson") else {
            throw ReadError.entryPathInvalid(path)
        }
        let storeName = String(parts[0])
        let entityName = String(parts[1].dropLast(".ndjson".count))
        guard storeName == "private" || storeName == "shared" else {
            throw ReadError.entryPathInvalid(path)
        }
        // Count by counting newlines (each DTO is one line).
        let count = ndjson.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
        return BackupEntityEntry(
            entityName: entityName,
            storeName: storeName,
            count: count,
            ndjson: ndjson
        )
    }

    // MARK: - Per-line iteration

    /// Iterates each JSON line in an entry's NDJSON body, yielding `Data` for
    /// each DTO. Callers typically run this inside the importer, decoding each
    /// line into the appropriate DTO type for the entity.
    public static func ndjsonLines(in entry: BackupEntityEntry) -> [Data] {
        var lines: [Data] = []
        var cursor = entry.ndjson.startIndex
        while cursor < entry.ndjson.endIndex {
            guard let newlineIdx = entry.ndjson[cursor...].firstIndex(of: 0x0A) else {
                // Trailing content without newline — still a valid line.
                lines.append(entry.ndjson[cursor..<entry.ndjson.endIndex])
                break
            }
            if newlineIdx > cursor {
                lines.append(entry.ndjson[cursor..<newlineIdx])
            }
            cursor = entry.ndjson.index(after: newlineIdx)
        }
        return lines
    }
}
