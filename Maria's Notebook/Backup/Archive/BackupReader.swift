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

public enum BackupReader {
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
    }

    public enum ReadError: LocalizedError {
        case notArchiveFormat
        case manifestMissing
        case manifestMalformed(reason: String)
        case unsupportedFormatVersion(found: Int, supported: ClosedRange<Int>)
        case entryPathInvalid(String)

        public var errorDescription: String? {
            switch self {
            case .notArchiveFormat:
                return "Backup file is not a supported archive \u{2014} files from app versions " +
                    "before the v17 format cannot be imported."
            case .manifestMissing:
                return "Backup is missing its manifest entry."
            case .manifestMalformed(let reason):
                return "Backup manifest is malformed: \(reason)"
            case .unsupportedFormatVersion(let found, let supported):
                return "Backup format version \(found) is not supported by this app " +
                    "(supported: v\(supported.lowerBound)\u{2013}v\(supported.upperBound))."
            case .entryPathInvalid(let path):
                return "Backup entry has an unexpected path: '\(path)' (expected '<store>/<EntityName>.ndjson')."
            }
        }
    }

    /// Supported format range. Bump the upper bound when we add a new format
    /// version (and keep the reader backward-compatible for the lower bound).
    /// v20 adds Guardian/ParentCommunication entries; v19 wraps the same
    /// entries in an encrypted AEA container; v18 added Stories/Book Club/
    /// Year Plan/Day Pad entries; v17/v18 files still read (plain compressed
    /// container, new entries simply absent).
    public static let supportedFormatVersions: ClosedRange<Int> = 17...21

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
        guard BackupArchive.isBackupArchive(at: url) else {
            throw ReadError.notArchiveFormat
        }

        var manifest: BackupArchiveManifest?
        var preferences: PreferencesDTO?
        var entries: [BackupEntityEntry] = []

        try BackupArchive.read(from: url, encryptionKey: keyProvider) { path, data in
            switch path {
            case "manifest.json":
                manifest = try decodeManifest(from: data)
            case "preferences.json":
                do {
                    preferences = try decodePreferences(from: data)
                } catch {
                    let msg = "Backup preferences entry failed to decode; " +
                        "restore will keep current settings: \(error.localizedDescription)"
                    logger.warning("\(msg, privacy: .public)")
                }
            default:
                if let entry = try parseEntityEntry(path: path, ndjson: data) {
                    entries.append(entry)
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

        let readerMsg = "BackupReader decoded v\(manifest.formatVersion) backup with \(entries.count) entity entries"
        logger.info("\(readerMsg, privacy: .public)")
        return DecodedBackup(manifest: manifest, entries: entries, preferences: preferences)
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

        try BackupArchive.read(from: url, encryptionKey: keyProvider) { path, data in
            switch path {
            case "manifest.json":
                manifest = try decodeManifest(from: data)
            case "preferences.json":
                break
            default:
                if let entry = try parseEntityEntry(path: path, ndjson: data) {
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
        return StructureVerification(manifest: manifest, entryLineCounts: lineCounts)
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
