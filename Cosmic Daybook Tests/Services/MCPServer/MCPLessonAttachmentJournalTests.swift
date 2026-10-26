import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What the write journal keeps of the lesson-file tools (attach, replace and
/// remove, each citing the lesson and the file; nothing for a refusal, a call
/// that changed nothing, or an unconfirmed remove), and the " · files: …"
/// suffix on `find_lessons` and `list_lessons_by_area` lines.
@Suite("MCP Lesson Attachment Journal and Lists")
@MainActor
struct MCPLessonAttachmentJournalTests {

    private actor WriteCollector {
        private(set) var records: [MCPWriteRecord] = []
        func add(_ record: MCPWriteRecord) { records.append(record) }
    }

    /// Calls `tool` through the request handler; returns whether the reply was an error.
    @discardableResult
    private func send(
        _ tool: String, _ arguments: [String: Any], to handler: MCPRequestHandler
    ) async throws -> Bool {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": tool, "arguments": arguments]
        ]
        let data = await handler.handle(line: try JSONSerialization.data(withJSONObject: body))
        let line = try #require(data)
        let reply = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        let result = try #require(reply["result"] as? [String: Any])
        return try #require(result["isError"] as? Bool)
    }

    @Test("Attach, replace and remove are journaled with both citations; refusals and no-ops are not")
    func journal() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let collector = WriteCollector()
        let handler = MCPRequestHandler(
            serverVersion: "1.0-test", tools: fixture.tools, onWrite: { await collector.add($0) }
        )
        let lessonID = try #require(fixture.lesson.id?.uuidString)
        let source = try fixture.write(LessonFileToolFixture.pdf(0.1), named: "circle.pdf")
        let path = source.path

        // Attach (journaled), the same title again (refused), the same bytes (no-op).
        #expect(try await send("attach_file_to_lesson", ["lesson": lessonID, "path": path], to: handler) == false)
        #expect(try await send("attach_file_to_lesson", ["lesson": lessonID, "path": path], to: handler) == true)
        #expect(try await send(
            "attach_file_to_lesson", ["lesson": lessonID, "path": path, "replace_existing": true], to: handler
        ) == false)
        // A real replace (journaled).
        try fixture.write(LessonFileToolFixture.pdf(0.9), named: "circle.pdf")
        #expect(try await send(
            "attach_file_to_lesson", ["lesson": lessonID, "path": path, "replace_existing": true], to: handler
        ) == false)
        // A path outside the folders (refused).
        let outside = try fixture.write(LessonFileToolFixture.pdf(), named: "secret.pdf", in: fixture.outside)
        #expect(try await send(
            "attach_file_to_lesson", ["lesson": lessonID, "path": outside.path], to: handler
        ) == true)
        // Remove: the report (not journaled), then the confirmed remove (journaled).
        let attachmentID = try #require(try fixture.stored().first?.id?.uuidString)
        #expect(try await send("remove_lesson_attachment", ["attachment": attachmentID], to: handler) == false)
        #expect(try await send(
            "remove_lesson_attachment", ["attachment": attachmentID, "confirm": true], to: handler
        ) == false)

        let records = await collector.records
        #expect(records.map(\.tool) == ["attach_file_to_lesson", "attach_file_to_lesson", "remove_lesson_attachment"])
        #expect(records.map(\.destructive) == [false, false, true])
        #expect(records[0].receipt.hasPrefix("Attached "))
        #expect(records[1].receipt.hasPrefix("Replaced "))
        let both: [MCPWriteRecord.Citation] = [
            .init(kind: "lesson", id: lessonID), .init(kind: "lessonAttachment", id: attachmentID)
        ]
        for record in records {
            #expect(record.citations.count == 2, "\(record.tool): \(record.citations)")
            for citation in both {
                #expect(record.citations.contains(citation), "\(record.tool): \(record.citations)")
            }
        }
        #expect(try fixture.stored().isEmpty)
    }

    // MARK: - Files suffix

    @Test("find_lessons ends a lesson's line with its files; five show as three plus \"+2 more\"")
    func findLessonsSuffix() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let other = CoreDataTestHelpers.seedLesson(
            in: fixture.context, name: "Circumference", area: "Geometry", sequence: "Circle"
        )
        other.id = UUID()
        try fixture.context.save()
        let one = try fixture.write(LessonFileToolFixture.pdf(), named: "circumference.pdf")
        _ = try await fixture.call("attach_file_to_lesson", ["lesson": "Circumference", "path": .string(one.path)])

        let few = try await fixture.call("find_lessons", ["query": "Circumference"])
        #expect(few.hasSuffix("Circumference — Geometry › Circle · files: 'circumference'"))

        for index in 1...5 {
            let source = try fixture.write(LessonFileToolFixture.pdf(CGFloat(index) / 10), named: "page \(index).pdf")
            _ = try await fixture.call("attach_file_to_lesson", fixture.attach(source.path))
            // Newest first, so each needs its own moment.
            let record = try #require(fixture.context.safeFetch(CDFetchRequest(CDLessonAttachment.self))
                .first { $0.title == "page \(index)" })
            record.attachedAt = Date(timeIntervalSince1970: 1_790_000_000 + Double(index))
        }
        try fixture.context.save()

        let many = try await fixture.call("find_lessons", ["query": "Area of a Circle"])
        #expect(many.hasSuffix(" · files: 'page 5', 'page 4', 'page 3', +2 more"))
        // A plain lesson line, untouched, for a lesson with no files.
        let none = CoreDataTestHelpers.seedLesson(
            in: fixture.context, name: "Radius", area: "Geometry", sequence: "Circle"
        )
        none.id = UUID()
        try fixture.context.save()
        let plain = try await fixture.call("find_lessons", ["query": "Radius"])
        #expect(plain == "- " + MCPNotebookTools.describeLesson(none))
    }

    @Test("list_lessons_by_area carries the suffix, and a sequence-wide file doesn't mark its siblings")
    func listLessonsByAreaSuffix() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        fixture.lesson.orderInSequence = 0
        let sibling = CoreDataTestHelpers.seedLesson(
            in: fixture.context, name: "Circumference", area: "Geometry", sequence: "Circle"
        )
        sibling.id = UUID()
        sibling.orderInSequence = 1
        try fixture.context.save()
        let own = try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf")
        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(own.path, title: "Area — album pages"))
        let shared = try fixture.write(LessonFileToolFixture.png(), named: "parts.png")
        try LessonAttachmentService(context: fixture.context, storage: fixture.storage).add(
            fileAt: shared, to: sibling, scope: .sequence, allowedTypes: LessonAttachmentService.pdfOrImage
        )

        let listing = try await fixture.call("list_lessons_by_area", ["area": "Geometry", "sub_area": "Circle"])
        let lines = listing.split(separator: "\n").map(String.init)

        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("1. [lesson id=") && lines[1].hasSuffix(" · files: 'Area — album pages'"))
        #expect(lines[2] == "2. " + MCPNotebookTools.describeLesson(sibling))
    }
}
