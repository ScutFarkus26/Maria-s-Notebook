import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Grounded Notebook Chat")
struct ChatGroundingTests {
    @Test("Evidence sources survive chat message encoding")
    func messageSourcesRoundTrip() throws {
        let source = EvidenceReference(
            entityKind: .note,
            entityID: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Golden Beads observation",
            excerpt: "Counted independently."
        )
        let message = ChatMessage(
            role: .assistant,
            content: "The record shows…",
            sources: [source]
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.sources == [source])
    }

    @Test("Older chat messages decode with an empty source list")
    func oldMessagesRemainReadable() throws {
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let object: [String: Any] = [
            "id": id.uuidString,
            "role": "assistant",
            "content": "Older answer",
            "timestamp": timestamp.timeIntervalSinceReferenceDate,
            "isEscalationPrompt": false
        ]
        let json = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(decoded.sources.isEmpty)
    }

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @Test("Source collector deduplicates by record identity")
    func collectorDeduplicatesSources() async {
        let id = UUID()
        let collector = EvidenceSourceCollector()
        let first = EvidenceReference(
            entityKind: .note,
            entityID: id,
            date: nil,
            title: "First title",
            excerpt: "First"
        )
        let updated = EvidenceReference(
            entityKind: .note,
            entityID: id,
            date: Date(),
            title: "Updated title",
            excerpt: "Updated"
        )
        await collector.record(first)
        await collector.record(updated)
        let sources = await collector.consume()
        #expect(sources.count == 1)
        #expect(sources.first?.title == "Updated title")
        let emptied = await collector.consume()
        #expect(emptied.isEmpty)
    }
    #endif
}
