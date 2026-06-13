// BackupArchive.swift
// Thin Swift wrapper around AppleArchive for v17+ backup files.
//
// Two on-disk containers, told apart by the first 4 bytes:
//
//   v19+ (current write format) — Apple Encrypted Archive, magic "AEA1".
//     AES-CTR + HMAC (profile hkdf_sha256_aesctr_hmac__symmetric__none) with
//     a 256-bit symmetric key from the user's iCloud Keychain
//     (`BackupEncryptionKeyStore`). LZFSE compression happens inside the AEA
//     layer via the encryption context.
//
//   v17/v18 (read-only) — plain LZFSE compressed container, magic "pbz" +
//     algorithm byte (e.g. "pbzE"). Still readable so existing backups and
//     checkpoints restore; no longer written.
//
//     Entries (same layout in both containers):
//       manifest.json
//       preferences.json
//       private/Note.ndjson
//       shared/Student.ndjson
//       …
//
// Each entry is a regular file inside the archive. NDJSON entries hold one
// JSON DTO per line (one Core Data row each).
//
// API is closure-based: the file/stream lifetime is bounded to the closure so
// the C-pointer-backed AppleArchive classes never escape and we don't need an
// actor wrapper. Both methods are synchronous and CPU/IO-bound — callers
// (`BackupWriter`/`BackupReader`) invoke them from off-main-actor contexts.

import Foundation
import AppleArchive
import CryptoKit
import System

public enum BackupArchive {

    /// Refuse to allocate more than this for a single entry. A well-formed
    /// backup entry is one entity type's NDJSON (a few MB at most); a header
    /// declaring more than this is a corrupt or hostile file, not a backup.
    public static let maxEntrySize: UInt64 = 1 << 30 // 1 GiB

    // MARK: - Errors

    public enum ArchiveError: LocalizedError {
        case cannotOpenFileForWrite(URL)
        case cannotOpenFileForRead(URL)
        case compressionStreamFailed
        case decompressionStreamFailed
        case encryptionContextFailed
        case encryptionStreamFailed
        case decryptionStreamFailed
        case encodeStreamFailed
        case decodeStreamFailed
        case missingHeaderField(String)
        case entryTooLarge(path: String, size: UInt64)
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
            case .encryptionContextFailed:
                return "Failed to read the backup's encryption header"
            case .encryptionStreamFailed:
                return "Failed to initialize AEA encryption stream"
            case .decryptionStreamFailed:
                return "Failed to initialize AEA decryption stream \u{2014} the file may be corrupt " +
                    "or encrypted with a different key"
            case .encodeStreamFailed:
                return "Failed to initialize archive encode stream"
            case .decodeStreamFailed:
                return "Failed to initialize archive decode stream"
            case .missingHeaderField(let name):
                return "Backup entry header missing required field '\(name)'"
            case .entryTooLarge(let path, let size):
                return "Backup entry '\(path)' declares an implausible size (\(size) bytes); " +
                    "refusing to read a corrupt or hostile file"
            case .sizeMismatch(let expected, let actual):
                return "Backup entry size mismatch: header says \(expected) bytes, read \(actual)"
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }

    // MARK: - Container Detection

    private static let aeaMagic = Data([0x41, 0x45, 0x41, 0x31])      // "AEA1" — Apple Encrypted Archive
    private static let compressedMagicPrefix = Data([0x70, 0x62, 0x7A]) // "pbz" + algorithm byte

    /// Checks whether the file at `url` is any archive container this module
    /// can read: an encrypted v19+ AEA ("AEA1") or a plain compressed v17/v18
    /// container ("pbz*"). Reads only the first 4 bytes.
    public static func isBackupArchive(at url: URL) -> Bool {
        guard let prefix = magicBytes(at: url) else { return false }
        return prefix == aeaMagic || prefix.prefix(3) == compressedMagicPrefix
    }

    /// True only for encrypted (v19+) archives. Used to report `encryptUsed`
    /// accurately in summaries and verification info.
    public static func isEncryptedArchive(at url: URL) -> Bool {
        magicBytes(at: url) == aeaMagic
    }

    private static func magicBytes(at url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 4), prefix.count == 4 else { return nil }
        return prefix
    }

    // MARK: - Write

    /// Writes an encrypted (v19) backup file. The closure receives an
    /// `Appender` used to add entries; the file is finalized when the closure
    /// returns.
    ///
    /// Entries are written in the order they are appended. Use a stable order
    /// (manifest first, then store-prefixed entity NDJSON entries) so readers
    /// can rely on predictable layout.
    ///
    /// The file is created with 0600 permissions — backups hold student
    /// records and should never be world-readable, even before encryption.
    public static func write(
        to url: URL,
        encryptionKey: SymmetricKey,
        body: (Appender) throws -> Void
    ) throws {
        let filePath = FilePath(url.path)

        guard let fileStream = ArchiveByteStream.fileStream(
            path: filePath,
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: FilePermissions(rawValue: 0o600)
        ) else {
            throw ArchiveError.cannotOpenFileForWrite(url)
        }
        defer { try? fileStream.close() }

        // LZFSE runs inside the AEA layer, so there is no separate
        // compression stream on the encrypted path.
        let context = ArchiveEncryptionContext(
            profile: .hkdf_sha256_aesctr_hmac__symmetric__none,
            compressionAlgorithm: .lzfse
        )
        try context.setSymmetricKey(encryptionKey)

        guard let encryptionStream = ArchiveByteStream.encryptionStream(
            writingTo: fileStream,
            encryptionContext: context
        ) else {
            throw ArchiveError.encryptionStreamFailed
        }
        defer { try? encryptionStream.close() }

        guard let encodeStream = ArchiveStream.encodeStream(
            writingTo: encryptionStream
        ) else {
            throw ArchiveError.encodeStreamFailed
        }
        defer { try? encodeStream.close() }

        let appender = Appender(stream: encodeStream)
        try body(appender)
    }

    // MARK: - Read

    /// Reads a backup archive of either container format. The `consumer`
    /// closure is invoked once per entry. Return `false` from the closure to
    /// stop iteration early.
    ///
    /// `encryptionKey` is only invoked for encrypted ("AA01") files, so plain
    /// v17/v18 archives stay readable without Keychain access.
    public static func read(
        from url: URL,
        encryptionKey: () throws -> SymmetricKey,
        consumer: (_ path: String, _ data: Data) throws -> Bool
    ) throws {
        let filePath = FilePath(url.path)

        guard let fileStream = ArchiveByteStream.fileStream(
            path: filePath,
            mode: .readOnly,
            options: [],
            permissions: FilePermissions(rawValue: 0o600)
        ) else {
            throw ArchiveError.cannotOpenFileForRead(url)
        }
        defer { try? fileStream.close() }

        if isEncryptedArchive(at: url) {
            guard let context = ArchiveEncryptionContext(from: fileStream) else {
                throw ArchiveError.encryptionContextFailed
            }
            try context.setSymmetricKey(try encryptionKey())

            guard let decryptionStream = ArchiveByteStream.decryptionStream(
                readingFrom: fileStream,
                encryptionContext: context
            ) else {
                throw ArchiveError.decryptionStreamFailed
            }
            defer { try? decryptionStream.close() }

            try consumeEntries(readingFrom: decryptionStream, consumer: consumer)
        } else {
            guard let decompressionStream = ArchiveByteStream.decompressionStream(
                readingFrom: fileStream
            ) else {
                throw ArchiveError.decompressionStreamFailed
            }
            defer { try? decompressionStream.close() }

            try consumeEntries(readingFrom: decompressionStream, consumer: consumer)
        }
    }

    private static func consumeEntries(
        readingFrom byteStream: ArchiveByteStream,
        consumer: (_ path: String, _ data: Data) throws -> Bool
    ) throws {
        guard let decodeStream = ArchiveStream.decodeStream(
            readingFrom: byteStream
        ) else {
            throw ArchiveError.decodeStreamFailed
        }
        defer { try? decodeStream.close() }

        while let header = try decodeStream.readHeader() {
            let (path, size) = try Self.extractPathAndSize(from: header)
            guard size <= maxEntrySize else {
                throw ArchiveError.entryTooLarge(path: path, size: size)
            }
            let data = try Self.readBlob(size: size, from: decodeStream)
            let shouldContinue = try consumer(path, data)
            if !shouldContinue { return }
        }
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
        // Bounded by maxEntrySize in consumeEntries before we get here.
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

    /// Writes entries into an open archive encode stream. Created by
    /// `write(to:encryptionKey:body:)` and valid only for the duration of the
    /// closure.
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
