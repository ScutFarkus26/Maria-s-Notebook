// BackupReader.swift
// Decodes a v17 AEA-framed backup file into a manifest + ordered entries.
//
// Reads only v17 files. Non-AEA files are rejected for manual import; the
// older envelope path remains only for internal rollback checkpoints.

import Foundation
import OSLog

public enum BackupReader {
    private static let logger = Logger.backup

    public struct DecodedBackup: Sendable {
        public let manifest: BackupArchiveManifest
        public let entries: [BackupEntityEntry]
        public let preferences: PreferencesDTO?
    }

    public enum ReadError: LocalizedError {
        case notAEAFormat
        case manifestMissing
        case manifestMalformed(reason: String)
        case unsupportedFormatVersion(found: Int, supported: ClosedRange<Int>)
        case entryPathInvalid(String)

        public var errorDescription: String? {
            switch self {
            case .notAEAFormat:
                return "Backup file is not a v17 AppleArchive — legacy decoder should handle this."
            case .manifestMissing:
                return "Backup is missing its manifest entry."
            case .manifestMalformed(let reason):
                return "Backup manifest is malformed: \(reason)"
            case .unsupportedFormatVersion(let found, let supported):
                return "Backup format version \(found) is not supported by this app " +
                    "(supported: v\(supported.lowerBound)–v\(supported.upperBound))."
            case .entryPathInvalid(let path):
                return "Backup entry has an unexpected path: '\(path)' (expected '<store>/<EntityName>.ndjson')."
            }
        }
    }

    /// Supported v17+ range. Bump the upper bound when we add a new format
    /// version (and keep the reader backward-compatible for the lower bound).
    /// v18 adds Stories/Book Club/Year Plan/Day Pad NDJSON entries; v17 files
    /// still read (the new entries are simply absent).
    public static let supportedFormatVersions: ClosedRange<Int> = 17...18

    // MARK: - Public API

    /// Reads a v17 AEA backup file fully into memory. Returns the manifest,
    /// preferences (if present), and one entry per non-empty entity NDJSON
    /// payload.
    public static func read(from url: URL) throws -> DecodedBackup {
        guard BackupArchive.isAEAFormat(at: url) else {
            throw ReadError.notAEAFormat
        }

        var manifest: BackupArchiveManifest?
        var preferences: PreferencesDTO?
        var entries: [BackupEntityEntry] = []

        try BackupArchive.read(from: url) { path, data in
            switch path {
            case "manifest.json":
                manifest = try decodeManifest(from: data)
            case "preferences.json":
                preferences = try? decodePreferences(from: data)
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
