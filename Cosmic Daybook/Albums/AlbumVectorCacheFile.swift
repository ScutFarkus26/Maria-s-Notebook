// AlbumVectorCacheFile.swift
// One album's embedding vectors as the semantic index caches them on disk:
// raw Float32 behind a small versioned header, read back bit for bit.

import Foundation

/// The vectors `AlbumSemanticIndex` caches for one album in Application
/// Support (`AlbumSemanticIndex/<album>.vectors.bin`), with what decides
/// whether they still fit the album: the PDF's modification date and the
/// title model that embedded them.
///
/// The file is a header and then every vector's floats, little-endian like
/// every Apple platform:
///
///     "ALBV" · version UInt32 · modified Float64 (seconds since 2001)
///     · title model name: byte count UInt32, UTF-8
///     · title rows UInt32 · title dimension UInt32
///     · body rows UInt32 (all ones when there are no body vectors) · body dimension UInt32
///     · the title vectors' floats, row after row · then the body vectors'
///
/// The floats are the embedder's own bits, so an album read back ranks
/// exactly as it did when it was embedded. It replaces a JSON file of the same
/// vectors (`<album>.vectors2.json`, about three times the size, and its parse
/// was most of a library load); `legacyJSON(at:)` reads one of those so it
/// can be written back in this form instead of embedding the album again.
nonisolated struct AlbumVectorCacheFile: Equatable, Sendable {
    let modified: Date
    let titleBackend: String
    let titles: [[Float]]
    let bodies: [[Float]]?

    /// Bumped whenever the layout changes. A file of any other version is a
    /// cache miss: the album is embedded again and the file rewritten.
    static let formatVersion: UInt32 = 1

    private static let magic: [UInt8] = Array("ALBV".utf8)
    /// The body row count that means "no body vectors" (the contextual model
    /// was unavailable), as distinct from an album with no lessons.
    private static let noBodies = UInt32.max

    static func url(for albumID: String, in directory: URL) -> URL {
        directory.appendingPathComponent(albumID + ".vectors.bin")
    }

    /// Where the JSON cache that came before this one lived.
    static func legacyJSONURL(for albumID: String, in directory: URL) -> URL {
        directory.appendingPathComponent(albumID + ".vectors2.json")
    }

    /// Whether these vectors were built for the album as it is now: from the
    /// PDF modified at `date` (within a second), one title vector per lesson,
    /// by the title model this process uses.
    func fits(modified date: Date, titleCount: Int, backend: String) -> Bool {
        abs(modified.timeIntervalSince(date)) < 1
            && titles.count == titleCount
            && titleBackend == backend
    }

    // MARK: Reading and writing

    /// The album's cached vectors while they still fit it. A JSON cache from a
    /// build before this format is read once and written back in this form:
    /// its vectors are the embedder's own, so the album is not embedded again.
    static func cached(albumID: String, modified: Date, titleCount: Int, backend: String,
                       in directory: URL) -> AlbumVectorCacheFile? {
        if let cached = read(from: url(for: albumID, in: directory)),
           cached.fits(modified: modified, titleCount: titleCount, backend: backend) {
            return cached
        }
        let legacyURL = legacyJSONURL(for: albumID, in: directory)
        guard let legacy = legacyJSON(at: legacyURL),
              legacy.fits(modified: modified, titleCount: titleCount, backend: backend) else { return nil }
        if legacy.write(to: url(for: albumID, in: directory)) {
            try? FileManager.default.removeItem(at: legacyURL)
        }
        return legacy
    }

    /// Caches freshly embedded vectors for the album, and drops a JSON cache
    /// from before (it was for another modification date or title model).
    func save(albumID: String, in directory: URL) {
        guard write(to: Self.url(for: albumID, in: directory)) else { return }
        try? FileManager.default.removeItem(at: Self.legacyJSONURL(for: albumID, in: directory))
    }

    /// The cache file at `url`; nil when there is none or it isn't one this
    /// format reads. Mapped rather than copied into memory: its bytes are read
    /// once, straight into the vectors.
    static func read(from url: URL) -> AlbumVectorCacheFile? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return decode(data)
    }

    /// Writes the whole file or nothing; false when it couldn't be encoded or
    /// written.
    @discardableResult
    func write(to url: URL) -> Bool {
        guard let data = encoded() else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// A JSON cache from before this format, decoded exactly as those builds
    /// read it.
    static func legacyJSON(at url: URL) -> AlbumVectorCacheFile? {
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(LegacyCachedVectors.self, from: data) else { return nil }
        return AlbumVectorCacheFile(modified: cached.modified, titleBackend: cached.titleBackend,
                                    titles: cached.titles, bodies: cached.bodies)
    }

    /// The JSON those builds wrote (their `AlbumSemanticIndex.CachedVectors`).
    nonisolated private struct LegacyCachedVectors: Decodable {
        let modified: Date
        let titleBackend: String
        let titles: [[Float]]
        let bodies: [[Float]]?
    }

    // MARK: Encoding

    /// The file's bytes; nil when a vector set's rows differ in length. The
    /// embedders give every row of a set one dimension, and the layout keeps
    /// one per set.
    func encoded() -> Data? {
        guard let titleShape = Self.shape(of: titles) else { return nil }
        var bodyShape = (rows: Self.noBodies, dimension: UInt32(0))
        if let bodies {
            guard let shape = Self.shape(of: bodies) else { return nil }
            bodyShape = shape
        }
        let backendBytes = Array(titleBackend.utf8)
        guard let backendCount = UInt32(exactly: backendBytes.count) else { return nil }
        let floatCount = titles.reduce(0) { $0 + $1.count } + (bodies ?? []).reduce(0) { $0 + $1.count }
        var data = Data()
        data.reserveCapacity(40 + backendBytes.count + floatCount * MemoryLayout<Float>.size)
        data.append(contentsOf: Self.magic)
        Self.append(Self.formatVersion, to: &data)
        Self.append(modified.timeIntervalSinceReferenceDate.bitPattern, to: &data)
        Self.append(backendCount, to: &data)
        data.append(contentsOf: backendBytes)
        for value in [titleShape.rows, titleShape.dimension, bodyShape.rows, bodyShape.dimension] {
            Self.append(value, to: &data)
        }
        for row in titles {
            row.withUnsafeBufferPointer { data.append($0) }
        }
        for row in bodies ?? [] {
            row.withUnsafeBufferPointer { data.append($0) }
        }
        return data
    }

    /// The row count and the one dimension every row has; nil for ragged rows,
    /// or a count that doesn't fit the header.
    private static func shape(of rows: [[Float]]) -> (rows: UInt32, dimension: UInt32)? {
        let dimension = rows.first?.count ?? 0
        guard rows.allSatisfy({ $0.count == dimension }),
              let rowCount = UInt32(exactly: rows.count), rowCount != noBodies,
              let width = UInt32(exactly: dimension) else { return nil }
        return (rowCount, width)
    }

    private static func append<Integer: FixedWidthInteger>(_ value: Integer, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    // MARK: Decoding

    /// Reads bytes `encoded()` wrote. Anything else (another version, a short
    /// or overlong file, counts that don't add up) is nil.
    static func decode(_ data: Data) -> AlbumVectorCacheFile? {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> AlbumVectorCacheFile? in
            var reader = ByteReader(raw: raw)
            guard reader.bytes(Self.magic.count).map({ Array($0) }) == Self.magic,
                  reader.integer(UInt32.self) == Self.formatVersion,
                  let modifiedBits = reader.integer(UInt64.self),
                  let backendCount = reader.integer(UInt32.self),
                  let backendBytes = reader.bytes(Int(backendCount)),
                  let titleBackend = String(bytes: backendBytes, encoding: .utf8),
                  let titleRows = reader.integer(UInt32.self),
                  let titleDimension = reader.integer(UInt32.self),
                  let bodyRows = reader.integer(UInt32.self),
                  let bodyDimension = reader.integer(UInt32.self),
                  let titles = reader.rows(Int(titleRows), dimension: Int(titleDimension)) else { return nil }
            var bodies: [[Float]]?
            if bodyRows != Self.noBodies {
                guard let rows = reader.rows(Int(bodyRows), dimension: Int(bodyDimension)) else { return nil }
                bodies = rows
            }
            guard reader.isAtEnd else { return nil }
            return AlbumVectorCacheFile(
                modified: Date(timeIntervalSinceReferenceDate: Double(bitPattern: modifiedBits)),
                titleBackend: titleBackend, titles: titles, bodies: bodies)
        }
    }

    /// Reads a buffer front to back and never past its end.
    nonisolated private struct ByteReader {
        let raw: UnsafeRawBufferPointer
        var offset = 0

        var isAtEnd: Bool { offset == raw.count }

        mutating func bytes(_ count: Int) -> UnsafeRawBufferPointer? {
            guard count >= 0, count <= raw.count - offset else { return nil }
            defer { offset += count }
            return UnsafeRawBufferPointer(rebasing: raw[offset..<(offset + count)])
        }

        mutating func integer<Integer: FixedWidthInteger>(_: Integer.Type) -> Integer? {
            bytes(MemoryLayout<Integer>.size).map { Integer(littleEndian: $0.loadUnaligned(as: Integer.self)) }
        }

        /// `count` rows of `dimension` floats, each copied into its own array.
        mutating func rows(_ count: Int, dimension: Int) -> [[Float]]? {
            let (rowBytes, wide) = dimension.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
            let (total, long) = count.multipliedReportingOverflow(by: rowBytes)
            guard !wide, !long, let block = bytes(total) else { return nil }
            return (0..<count).map { row in
                [Float](unsafeUninitializedCapacity: dimension) { buffer, initialized in
                    let start = row * rowBytes
                    UnsafeMutableRawBufferPointer(buffer)
                        .copyMemory(from: UnsafeRawBufferPointer(rebasing: block[start..<(start + rowBytes)]))
                    initialized = dimension
                }
            }
        }
    }
}
