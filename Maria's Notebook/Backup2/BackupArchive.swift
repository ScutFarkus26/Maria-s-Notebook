// BackupArchive.swift
// Thin Swift wrapper around AppleArchive (AEA) for v17 backup files.
//
// The Backup2 module writes one AEA-framed file per backup:
//
//     [AppleArchive container — first 4 bytes are "AA01"]
//       Entries (LZFSE-compressed, blockwise SHA-256 integrity):
//         manifest.json
//         private/Note.ndjson
//         private/AttendanceRecord.ndjson
//         shared/Student.ndjson
//         shared/Lesson.ndjson
//         …
//
// Each entry is a regular file inside the archive. NDJSON entries hold one
// JSON DTO per line (one Core Data row each). The first 4 bytes of any file
// produced by Backup2 are AEA's "AA01" magic — used by BackupReader to choose
// between AEA decode and legacy `.mtbbackup` decode (legacy files start with
// `{` from their JSON envelope).
//
// API is closure-based: the file/stream lifetime is bounded to the closure so
// the C-pointer-backed AppleArchive classes never escape and we don't need an
// actor wrapper. Both methods are synchronous; backups are I/O-bound and small
// enough that callers can invoke them on @MainActor without blocking the UI
// for noticeable time. Callers wanting async behavior can wrap in `Task`.

import Foundation
import AppleArchive
import System

public enum BackupArchive {

    // MARK: - Errors

    public enum ArchiveError: LocalizedError {
        case cannotOpenFileForWrite(URL)
        case cannotOpenFileForRead(URL)
        case compressionStreamFailed
        case decompressionStreamFailed
        case encodeStreamFailed
        case decodeStreamFailed
        case missingHeaderField(String)
        case sizeMismatch(expected: UInt64, actual: Int)
        case underlying(Error)

        public var errorDescription: String? {
            switch self {
            case .cannotOpenFileForWrite(let url):
                return "Could not open backup file for write at \(url.path)"
            case .cannotOpenFileForRead(let url):
                return "Could not open backup file for read at \(url.path)"
            case .compressionStreamFailed:
                return "Failed to initialize LZFSE compression stream"
            case .decompressionStreamFailed:
                return "Failed to initialize LZFSE decompression stream"
            case .encodeStreamFailed:
                return "Failed to initialize AEA encode stream"
            case .decodeStreamFailed:
                return "Failed to initialize AEA decode stream"
            case .missingHeaderField(let name):
                return "Backup entry header missing required field '\(name)'"
            case .sizeMismatch(let expected, let actual):
                return "Backup entry size mismatch: header says \(expected) bytes, read \(actual)"
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }

    // MARK: - Write

    /// Writes an AEA-framed backup file. The closure receives an `Appender`
    /// used to add entries; the file is finalized when the closure returns.
    ///
    /// Entries are written in the order they are appended. Use a stable order
    /// (manifest first, then store-prefixed entity NDJSON entries) so readers
    /// can rely on predictable layout.
    public static func write(
        to url: URL,
        body: (Appender) throws -> Void
    ) throws {
        let filePath = FilePath(url.path)

        guard let fileStream = ArchiveByteStream.fileStream(
            path: filePath,
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: FilePermissions(rawValue: 0o644)
        ) else {
            throw ArchiveError.cannotOpenFileForWrite(url)
        }
        defer { try? fileStream.close() }

        guard let compressionStream = ArchiveByteStream.compressionStream(
            using: .lzfse,
            writingTo: fileStream
        ) else {
            throw ArchiveError.compressionStreamFailed
        }
        defer { try? compressionStream.close() }

        guard let encodeStream = ArchiveStream.encodeStream(
            writingTo: compressionStream
        ) else {
            throw ArchiveError.encodeStreamFailed
        }
        defer { try? encodeStream.close() }

        let appender = Appender(stream: encodeStream)
        try body(appender)
    }

    // MARK: - Read

    /// Reads an AEA-framed backup file. The `consumer` closure is invoked once
    /// per entry. Return `false` from the closure to stop iteration early.
    public static func read(
        from url: URL,
        consumer: (_ path: String, _ data: Data) throws -> Bool
    ) throws {
        let filePath = FilePath(url.path)

        guard let fileStream = ArchiveByteStream.fileStream(
            path: filePath,
            mode: .readOnly,
            options: [],
            permissions: FilePermissions(rawValue: 0o644)
        ) else {
            throw ArchiveError.cannotOpenFileForRead(url)
        }
        defer { try? fileStream.close() }

        guard let decompressionStream = ArchiveByteStream.decompressionStream(
            readingFrom: fileStream
        ) else {
            throw ArchiveError.decompressionStreamFailed
        }
        defer { try? decompressionStream.close() }

        guard let decodeStream = ArchiveStream.decodeStream(
            readingFrom: decompressionStream
        ) else {
            throw ArchiveError.decodeStreamFailed
        }
        defer { try? decodeStream.close() }

        while let header = try decodeStream.readHeader() {
            let (path, size) = try Self.extractPathAndSize(from: header)
            let data = try Self.readBlob(size: size, from: decodeStream)
            let shouldContinue = try consumer(path, data)
            if !shouldContinue { return }
        }
    }

    /// Checks whether a file at `url` is an AEA-formatted backup (Backup2 v17+)
    /// or a legacy `.mtbbackup` JSON envelope (v5–v16). Reads only the first
    /// 4 bytes. Returns `true` for AEA, `false` for legacy.
    public static func isAEAFormat(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 4), prefix.count == 4 else { return false }
        return prefix == Data([0x41, 0x41, 0x30, 0x31]) // "AA01"
    }

    // MARK: - Header Helpers

    private static func extractPathAndSize(
        from header: ArchiveHeader
    ) throws -> (path: String, size: UInt64) {
        guard let pathField = header.field(forKey: ArchiveHeader.FieldKey("PAT")) else {
            throw ArchiveError.missingHeaderField("PAT")
        }
        let path: String
        switch pathField {
        case .string(_, let value):
            path = value
        default:
            throw ArchiveError.missingHeaderField("PAT(string)")
        }

        guard let sizeField = header.field(forKey: ArchiveHeader.FieldKey("DAT")) else {
            // DAT field exists as blob; if absent the entry has no body (skip).
            return (path, 0)
        }
        let size: UInt64
        switch sizeField {
        case .blob(_, let blobSize, _):
            size = UInt64(blobSize)
        default:
            throw ArchiveError.missingHeaderField("DAT(blob)")
        }
        return (path, size)
    }

    private static func readBlob(
        size: UInt64,
        from stream: ArchiveStream
    ) throws -> Data {
        guard size > 0 else { return Data() }
        // size is bounded by the manifest's per-entry caller (one NDJSON entry per
        // entity-type — bounded by entity count × DTO size; well under Int.max).
        let intSize = Int(size)
        var data = Data(count: intSize)
        try data.withUnsafeMutableBytes { rawBuffer in
            _ = try stream.readBlob(
                key: ArchiveHeader.FieldKey("DAT"),
                into: rawBuffer
            )
        }
        return data
    }

    // MARK: - Appender

    /// Writes entries into an open AEA encode stream. Created by `write(to:body:)`
    /// and valid only for the duration of the closure.
    public final class Appender {
        private let stream: ArchiveStream
        private let typeRegularFile: UInt64 = 0x46 // 'F' — see AppleArchive header type codes

        fileprivate init(stream: ArchiveStream) {
            self.stream = stream
        }

        /// Appends a regular-file entry at `path` with `data` as its body.
        /// `path` is the in-archive path (e.g. `"private/Note.ndjson"`).
        public func append(path: String, data: Data) throws {
            let header = ArchiveHeader()
            header.append(.string(
                key: ArchiveHeader.FieldKey("PAT"),
                value: path
            ))
            header.append(.uint(
                key: ArchiveHeader.FieldKey("TYP"),
                value: typeRegularFile
            ))
            header.append(.blob(
                key: ArchiveHeader.FieldKey("DAT"),
                size: UInt64(data.count),
                offset: 0
            ))
            try stream.writeHeader(header)
            try data.withUnsafeBytes { rawBuffer in
                try stream.writeBlob(
                    key: ArchiveHeader.FieldKey("DAT"),
                    from: rawBuffer
                )
            }
        }
    }
}
