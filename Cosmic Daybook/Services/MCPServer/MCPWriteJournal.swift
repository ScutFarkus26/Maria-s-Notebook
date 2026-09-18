//
//  MCPWriteJournal.swift
//  Cosmic Daybook
//
//  A device-local, append-only record of what was written over MCP.
//
//  Nothing on a record says where it came from, and nothing should: a note's
//  `reportedBy` / `reporterName` carry classroom-role meaning (guide or
//  assistant, and the speaker label the export prints), so stamping them with
//  the transport would mislabel the guide's own dictated observations. The
//  provenance lives here instead — beside the notebook, not inside it — as
//  one JSON line per successful write, holding the tool, the arguments, the
//  head of the receipt, and the ids the tool cited. That is enough to review
//  a filing session, or to walk one back with the update_* tools.
//
//  The file belongs to this device; it is not in Core Data and does not sync.
//

import Foundation
import OSLog

// MARK: - Record

/// One line of the journal: a single successful non-read-only tool call.
nonisolated struct MCPWriteRecord: Codable, Sendable, Equatable {
    /// An entity the call created or changed, as the tool's own result cited
    /// it. Album pages are cited `[albumPage album="…" page=…]` and carry no
    /// id, so they never appear here.
    nonisolated struct Citation: Codable, Sendable, Equatable {
        let kind: String
        let id: String
    }

    let id: UUID
    /// When the call returned. Written to the file as ISO 8601.
    let timestamp: Date
    let tool: String
    /// The call's arguments as compact JSON, with long strings and long
    /// arrays elided — a journal line should stay readable next to a batch
    /// of forty observations.
    let arguments: String
    /// The head of the tool's own result text.
    let receipt: String
    let citations: [Citation]
    /// The tool's `destructiveHint`: it deleted or retired something.
    let destructive: Bool
}

extension MCPWriteRecord {
    /// Longest string kept whole inside `arguments`.
    static let argumentStringLimit = 200
    /// Longest array kept whole inside `arguments`; the rest is counted off.
    static let argumentArrayLimit = 20
    /// How much of the tool's result text the receipt keeps.
    static let receiptLimit = 300

    /// Builds a record from a completed call. `id` and `timestamp` are
    /// injectable so tests can seed a journal with known lines.
    init(
        tool: String,
        arguments: [String: JSONValue],
        result: String,
        destructive: Bool,
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.tool = tool
        self.arguments = Self.compactJSON(.object(arguments))
        self.receipt = String(result.prefix(Self.receiptLimit))
        self.citations = Self.citations(in: result)
        self.destructive = destructive
    }

    /// The arguments as one line of JSON, keys sorted so two identical calls
    /// read identically in the journal.
    static func compactJSON(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(summarised(value)),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// Truncates long strings and counts off long arrays, recursively.
    static func summarised(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let text):
            guard text.count > argumentStringLimit else { return value }
            return .string(String(text.prefix(argumentStringLimit)) + "…")
        case .array(let items):
            let kept = items.prefix(argumentArrayLimit).map(summarised)
            guard items.count > argumentArrayLimit else { return .array(kept) }
            return .array(kept + [.string("… \(items.count - argumentArrayLimit) more")])
        case .object(let object):
            return .object(object.mapValues(summarised))
        default:
            return value
        }
    }

    /// Every `[kind id=<uuid>]` in the result text, first occurrence first.
    /// Anything whose id is not a UUID — `[note id=unknown]`, a documentation
    /// ellipsis, an album page — is not a citation and is skipped.
    static func citations(in text: String) -> [Citation] {
        var found: [Citation] = []
        var seen: Set<String> = []
        var rest = text[...]
        while let open = rest.firstIndex(of: "[") {
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "]") else { break }
            let body = rest[afterOpen..<close]
            if let marker = body.range(of: " id="),
               let citation = citation(kind: body[..<marker.lowerBound], id: body[marker.upperBound...]),
               seen.insert(citation.kind + citation.id).inserted {
                found.append(citation)
            }
            rest = rest[rest.index(after: close)...]
        }
        return found
    }

    private static func citation(kind: Substring, id: Substring) -> Citation? {
        let kindText = String(kind)
        let idText = String(id)
        guard !kindText.isEmpty, !kindText.contains(" "), UUID(uuidString: idText) != nil else {
            return nil
        }
        return Citation(kind: kindText, id: idText)
    }
}

// MARK: - Journal

/// The append-only file itself. An actor rather than a main-actor type
/// because the socket server's connection task calls it off the main thread,
/// and a serial actor is the whole of the locking the file needs.
actor MCPWriteJournal {
    static let shared = MCPWriteJournal(directory: MCPWriteJournal.defaultDirectory)

    /// Past this the file is halved. Roughly twenty thousand lines — far more
    /// than a season of filing, and small enough to rewrite in one gulp.
    static let maximumFileBytes = 2 * 1024 * 1024

    private let directory: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: Logger

    /// `directory` is injectable so tests write to a temporary directory.
    init(directory: URL) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("writes.jsonl")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.logger = Logger.app(category: "MCPWriteJournal")
    }

    /// `<Application Support>/MCP/`, resolved the way CoreDataStack resolves
    /// the store directory — inside the container, so it is as private as the
    /// notebook is.
    nonisolated static var defaultDirectory: URL {
        let manager = FileManager.default
        let base = (try? manager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? manager.temporaryDirectory
        return base.appendingPathComponent("MCP", isDirectory: true)
    }

    /// Where the journal is kept.
    var location: URL { fileURL }

    // MARK: Writing

    /// Appends one record. Journalling is bookkeeping: it must never turn a
    /// filed observation into a failed tool call, so every failure is logged
    /// and swallowed.
    func record(_ record: MCPWriteRecord) {
        do {
            var line = try encoder.encode(record)
            line.append(0x0A)
            try append(line)
            try capIfNeeded()
        } catch {
            logger.error("MCP write journal append failed: \(error, privacy: .public)")
        }
    }

    private func append(_ data: Data) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            manager.createFile(atPath: fileURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// Keeps the newest half once the file outgrows its cap.
    private func capIfNeeded() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? Int, size > Self.maximumFileBytes else { return }
        let lines = storedLines()
        guard lines.count > 1 else { return }
        let kept = lines.suffix(lines.count / 2)
        let text = kept.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: fileURL, options: .atomic)
    }

    // MARK: Reading

    /// Newest first. `until` is exclusive, matching `DayWindow.endExclusive`.
    /// A line that will not decode is skipped rather than failing the read —
    /// a half-written tail should not hide the season behind it.
    func records(
        since: Date? = nil, until: Date? = nil, tool: String? = nil, limit: Int = 50
    ) -> [MCPWriteRecord] {
        var results: [MCPWriteRecord] = []
        for line in storedLines().reversed() {
            guard results.count < limit else { break }
            guard let data = line.data(using: .utf8),
                  let record = try? decoder.decode(MCPWriteRecord.self, from: data) else { continue }
            if let since, record.timestamp < since { continue }
            if let until, record.timestamp >= until { continue }
            if let tool, record.tool != tool { continue }
            results.append(record)
        }
        return results
    }

    private func storedLines() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
