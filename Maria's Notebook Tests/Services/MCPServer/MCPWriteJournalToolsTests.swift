import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// Fixtures shared by the journal and the tool that reads it.
private enum Journal {
    /// A fresh directory per test: the journal creates it on first append.
    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MCPWriteJournal-\(UUID().uuidString)", isDirectory: true)
    }

    static func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A record with a known age, built through the memberwise initialiser so
    /// a test can hand-size `arguments` without going through truncation.
    static func record(
        tool: String,
        minutesAgo: Int,
        arguments: String = "{}",
        receipt: String = "done",
        citations: [MCPWriteRecord.Citation] = [],
        destructive: Bool = false
    ) -> MCPWriteRecord {
        MCPWriteRecord(
            id: UUID(),
            timestamp: Date().addingTimeInterval(TimeInterval(-60 * minutesAgo)),
            tool: tool,
            arguments: arguments,
            receipt: receipt,
            citations: citations,
            destructive: destructive
        )
    }

    /// The same encoding `MCPWriteJournal` writes, so a test can seed the file
    /// directly instead of appending thousands of times.
    static func line(for record: MCPWriteRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw MCPToolError("A journal line must be UTF-8.")
        }
        return text
    }

    static func seed(_ lines: [String], in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: directory.appendingPathComponent("writes.jsonl"))
    }
}

@Suite("MCP Write Journal")
struct MCPWriteJournalTests {

    @Test("Appended records read back newest first")
    func roundTripsNewestFirst() async throws {
        let directory = Journal.temporaryDirectory()
        defer { Journal.remove(directory) }
        let journal = MCPWriteJournal(directory: directory)

        await journal.record(Journal.record(tool: "create_observation", minutesAgo: 120))
        await journal.record(Journal.record(tool: "record_presentation", minutesAgo: 60))
        await journal.record(Journal.record(tool: "update_todo", minutesAgo: 5))

        let records = await journal.records()
        #expect(records.map(\.tool) == ["update_todo", "record_presentation", "create_observation"])
    }

    @Test("A missing file reads as empty")
    func missingFileIsEmpty() async {
        let directory = Journal.temporaryDirectory()
        defer { Journal.remove(directory) }
        let records = await MCPWriteJournal(directory: directory).records()
        #expect(records.isEmpty)
    }

    @Test("The window and tool filters narrow the read")
    func filtersNarrowTheRead() async throws {
        let directory = Journal.temporaryDirectory()
        defer { Journal.remove(directory) }
        let journal = MCPWriteJournal(directory: directory)
        await journal.record(Journal.record(tool: "create_observation", minutesAgo: 60 * 24 * 30))
        await journal.record(Journal.record(tool: "create_observation", minutesAgo: 30))
        await journal.record(Journal.record(tool: "update_todo", minutesAgo: 10))

        let recent = await journal.records(since: Date().addingTimeInterval(-60 * 60 * 24))
        #expect(recent.count == 2)

        let byTool = await journal.records(tool: "create_observation")
        #expect(byTool.count == 2)

        let ceiling = await journal.records(until: Date().addingTimeInterval(-60 * 20))
        #expect(ceiling.map(\.tool) == ["create_observation", "create_observation"])

        let capped = await journal.records(limit: 1)
        #expect(capped.map(\.tool) == ["update_todo"])
    }

    @Test("A malformed line is skipped, not fatal")
    func malformedLineIsSkipped() async throws {
        let directory = Journal.temporaryDirectory()
        defer { Journal.remove(directory) }
        let good = try Journal.line(for: Journal.record(tool: "update_work", minutesAgo: 5))
        try Journal.seed(["{not json at all", good, "   "], in: directory)

        let records = await MCPWriteJournal(directory: directory).records()
        #expect(records.map(\.tool) == ["update_work"])
    }

    @Test("Passing the cap keeps the newest half")
    func capKeepsTheNewestHalf() async throws {
        let directory = Journal.temporaryDirectory()
        defer { Journal.remove(directory) }
        // Each seeded line is ~12 KB, so 200 of them comfortably pass 2 MB.
        let padding = String(repeating: "p", count: 12_000)
        let seeded: [MCPWriteRecord] = (0..<200).map { index in
            Journal.record(tool: "seeded_\(index)", minutesAgo: 1_000 - index, arguments: padding)
        }
        try Journal.seed(try seeded.map(Journal.line), in: directory)

        let journal = MCPWriteJournal(directory: directory)
        await journal.record(Journal.record(tool: "newest", minutesAgo: 0))

        let kept = await journal.records(limit: 500)
        #expect(kept.count == 100)
        #expect(kept.first?.tool == "newest")
        #expect(kept.contains { $0.tool == "seeded_199" })
        #expect(!kept.contains { $0.tool == "seeded_0" })
    }

    // MARK: Record shaping

    @Test("Arguments are compacted: long strings truncated, long arrays counted off")
    func argumentsAreSummarised() {
        let long = String(repeating: "a", count: 250)
        let names: [JSONValue] = (0..<25).map { .string("child \($0)") }
        let record = MCPWriteRecord(
            tool: "assign_work",
            arguments: ["body": .string(long), "names": .array(names)],
            result: "done",
            destructive: false
        )
        #expect(record.arguments.contains(String(repeating: "a", count: 200) + "…"))
        #expect(!record.arguments.contains(String(repeating: "a", count: 201)))
        #expect(record.arguments.contains("… 5 more"))
        #expect(record.arguments.contains("child 19"))
        #expect(!record.arguments.contains("child 20"))
    }

    @Test("Citations are parsed from the full result; ids that are not UUIDs are skipped")
    func citationsAreParsed() {
        let note = UUID()
        let presentation = UUID()
        let text = """
            Recorded [note id=\(note.uuidString)] about Ora Levi, from \
            [presentation id=\(presentation.uuidString)].
            See [albumPage album="math.pdf" page=3] and [lesson id=unknown] and [note id=\(note.uuidString)].
            """
        let record = MCPWriteRecord(
            tool: "record_presentation", arguments: [:], result: text, destructive: false
        )
        #expect(record.citations == [
            MCPWriteRecord.Citation(kind: "note", id: note.uuidString),
            MCPWriteRecord.Citation(kind: "presentation", id: presentation.uuidString)
        ])
    }

    @Test("The receipt keeps the head of the result text")
    func receiptIsTruncated() {
        let text = String(repeating: "b", count: 400)
        let record = MCPWriteRecord(
            tool: "create_observation", arguments: [:], result: text, destructive: true
        )
        #expect(record.receipt.count == 300)
        #expect(record.destructive)
    }
}

// MARK: - The tool

@Suite("MCP Recent Writes Tool")
@MainActor
struct MCPRecentWritesToolTests {

    private func tool(journal: MCPWriteJournal) throws -> MCPToolDefinition {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context }, journal: journal)
        return try #require(tools.first { $0.name == "recent_mcp_writes" })
    }

    @Test("An empty journal says so")
    func emptyJournalSaysSo() async throws {
        let directory = Journal.temporaryDirectory()
        defer { Journal.remove(directory) }
        let output = try await tool(journal: MCPWriteJournal(directory: directory)).handler([:])
        #expect(output == "Nothing has been written over MCP in that window.")
    }

    @Test("A seeded journal prints a headline and its arguments, newest first")
    func printsSeededRecords() async throws {
        let directory = Journal.temporaryDirectory()
        defer { Journal.remove(directory) }
        let journal = MCPWriteJournal(directory: directory)
        await journal.record(Journal.record(
            tool: "discard_presentation", minutesAgo: 90,
            arguments: #"{"confirm":true}"#, receipt: "Discarded. [presentation id=x]",
            destructive: true
        ))
        let recent = Journal.record(
            tool: "record_presentation", minutesAgo: 5,
            arguments: #"{"lesson":"Checkerboard"}"#,
            receipt: "Recorded [presentation id=y]: Checkerboard to Ora Levi\n2 observation(s) linked."
        )
        await journal.record(recent)

        let output = try await tool(journal: journal).handler([:])
        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines[0] == "2 write(s) over MCP in the last 7 days:")

        let stamp = "\(MCPNotebookTools.dayString(recent.timestamp)) "
            + "\(MCPNotebookTools.timeString(recent.timestamp))"
        #expect(lines[1] == "- \(stamp) record_presentation → Recorded [presentation id=y]: "
            + "Checkerboard to Ora Levi · 2 observation(s) linked.")
        #expect(lines[2] == #"    args: {"lesson":"Checkerboard"}"#)
        #expect(lines[3].contains("discard_presentation (destructive) → Discarded."))
    }

    @Test("The tool filter and the day window reach the header")
    func filtersReachTheHeader() async throws {
        let directory = Journal.temporaryDirectory()
        defer { Journal.remove(directory) }
        let journal = MCPWriteJournal(directory: directory)
        await journal.record(Journal.record(tool: "update_todo", minutesAgo: 30))
        await journal.record(Journal.record(tool: "create_observation", minutesAgo: 30))

        let filtered = try await tool(journal: journal).handler(["tool": "update_todo"])
        #expect(filtered.hasPrefix("1 write(s) over MCP by update_todo in the last 7 days:"))

        let today = MCPNotebookTools.isoDay.string(from: Date())
        let windowed = try await tool(journal: journal).handler(["since": .string(today)])
        #expect(windowed.hasPrefix("2 write(s) over MCP since \(today):"))

        let old = MCPNotebookTools.isoDay.string(
            from: Date().addingTimeInterval(-60 * 60 * 24 * 30)
        )
        let empty = try await tool(journal: journal).handler(["until": .string(old)])
        #expect(empty == "Nothing has been written over MCP in that window.")
    }
}
