import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11, agent Q: Ask AI's name lookups and suggestions (#49).
@Suite("Ask AI fixes (10-11 Q)")
@MainActor
struct ChatFix1011Q {

    private struct SilentClient: MCPClientProtocol {
        func generateText(prompt: String, temperature: Double) async throws -> String { "" }
        func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { "{}" }
    }

    private struct Class {
        let dechter: CDStudent
        let krinsky: CDStudent
        let ora: CDStudent
    }

    private func seedEttys(in context: NSManagedObjectContext) -> Class {
        let dechter = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let krinsky = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Krinsky")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        for student in [dechter, krinsky, ora] {
            student.id = UUID()
        }
        return Class(dechter: dechter, krinsky: krinsky, ora: ora)
    }

    private func resolved(_ name: String, among students: [CDStudent]) -> CDStudent? {
        if case .success(let student) = NotebookToolStudentResolver.resolve(name, among: students) {
            return student
        }
        return nil
    }

    // MARK: #49

    @Test("Chat's student lookup takes the short name, with or without a period")
    func shortNameResolves() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let kids = seedEttys(in: context)
        let all = [kids.dechter, kids.krinsky, kids.ora]

        #expect(resolved("Etty D", among: all) === kids.dechter)
        #expect(resolved("etty k.", among: all) === kids.krinsky)
        #expect(resolved("Etty Dechter", among: all) === kids.dechter)
        #expect(resolved("Ora", among: all) === kids.ora)
    }

    @Test("A shared first name asks which child, naming each by her short name")
    func sharedFirstNameOffersShortNames() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let kids = seedEttys(in: context)
        guard case .failure(let message) = NotebookToolStudentResolver.resolve(
            "Etty", among: [kids.dechter, kids.krinsky, kids.ora]
        ) else {
            Issue.record("Two Ettys resolved to one child")
            return
        }
        #expect(message.contains("(Etty D)"))
        #expect(message.contains("(Etty K)"))
    }

    @Test("The suggestion cards and the prompt use short names")
    func suggestionsUseShortNames() throws {
        let context = try CoreDataTestHelpers.makeContext()
        _ = seedEttys(in: context)
        try #require(CoreDataTestHelpers.save(context))

        let session = ChatService(modelContext: context, mcpClient: SilentClient()).startSession()

        #expect(session.studentNames.sorted() == ["Etty D", "Etty K", "Ora P"])
        #expect(AIPrompts.chatAssistant.contains("short name"))
    }

    // MARK: #53 (chat)

    /// A model that answers with `answer`, counting its calls.
    private final class FakeModel: RoutableModelClient {
        let isAvailable = true
        let unavailabilityReason = ""
        private(set) var calls = 0
        private(set) var tools: [ChatToolContext] = []
        private let answer: (ChatToolContext) async throws -> String

        init(answer: @escaping (ChatToolContext) async throws -> String) {
            self.answer = answer
        }

        func generateText(prompt: String, temperature: Double) async throws -> String { "" }
        func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { "{}" }
        // swiftlint:disable:next function_parameter_count
        func streamChat(
            messages: [[String: String]], systemMessage: String?, temperature: Double,
            maxTokens: Int, tools: ChatToolContext,
            onText: @escaping @MainActor @Sendable (String) -> Void
        ) async throws -> String {
            calls += 1
            self.tools.append(tools)
            return try await answer(tools)
        }
    }

    private func source(_ title: String) -> EvidenceReference {
        EvidenceReference(entityKind: .note, entityID: UUID(), date: nil, title: title, excerpt: "")
    }

    private func ask(_ client: any MCPClientProtocol, tools: ChatToolContext) async throws -> String {
        try await client.streamChat(
            messages: [["role": "user", "content": "How is Etty D doing?"]], systemMessage: nil,
            temperature: 0.7, maxTokens: 256, tools: tools, onText: { _ in }
        )
    }

    @Test("When Private Cloud answers after the on-device model fails, the failed attempt's sources are dropped")
    func fallbackDropsStaleSources() async throws {
        let tools = ChatToolContext(try CoreDataTestHelpers.makeContext())
        let local = FakeModel { tools in
            await tools.sources.record(self.source("Looked up, then failed"))
            throw LocalModelError.contextTooLarge
        }
        let cloud = FakeModel { tools in
            await tools.sources.record(self.source("Used by Private Cloud"))
            return "From Private Cloud."
        }

        // Through the router's own chat wiring, so dropping its
        // `beforeFallback` would fail here (review (b) 2026-10-11).
        let answer = try await AIClientRouter.streamChat(
            local: local, cloud: { cloud }, cloudAllowed: true,
            messages: [["role": "user", "content": "How is Etty D doing?"]], systemMessage: nil,
            temperature: 0.7, maxTokens: 256, tools: tools, onText: { _ in }
        )

        #expect(answer == "From Private Cloud.")
        #expect(local.calls == 1)
        #expect(cloud.calls == 1)
        #expect(cloud.tools.first === tools)
        #expect(await tools.sources.consume().map(\.title) == ["Used by Private Cloud"])
    }

    @Test("A cancelled answer isn't sent again to Private Cloud")
    func cancelledIsNotRetried() async throws {
        let tools = ChatToolContext(try CoreDataTestHelpers.makeContext())
        let local = FakeModel { _ in
            try await Task.sleep(for: .seconds(30))
            return "Too late."
        }
        let cloud = FakeModel { _ in "From Private Cloud." }

        let work: (any MCPClientProtocol) async throws -> String = { try await self.ask($0, tools: tools) }
        let send = Task {
            try await AIClientRouter.route(local: local, cloud: { cloud }, cloudAllowed: true, work)
        }
        while local.calls == 0 { await Task.yield() }
        send.cancel()
        let result = await send.result

        #expect(cloud.calls == 0)
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test("Each chat's answer reads its own classroom and keeps its own sources")
    func eachChatHasItsOwnContext() async throws {
        let guide = try CoreDataTestHelpers.makeContext()
        let sample = try CoreDataTestHelpers.makeContext()
        let client = FakeModel { tools in
            if tools.context === guide { await tools.sources.record(self.source("Guide's note")) }
            return "Answer."
        }
        let guideChat = ChatService(modelContext: guide, mcpClient: client)
        let sampleChat = ChatService(modelContext: sample, mcpClient: client)
        var guideSession = guideChat.startSession()
        var sampleSession = sampleChat.startSession()

        _ = try await guideChat.sendMessageStreaming("Who read today?", session: &guideSession) { _ in }
        _ = try await sampleChat.sendMessageStreaming("Who read today?", session: &sampleSession) { _ in }

        // The first answer's tools still read its own classroom after the
        // second chat answered (they used to share one process-wide value).
        #expect(client.tools.count == 2)
        #expect(client.tools.first?.context === guide)
        #expect(client.tools.last?.context === sample)
        #expect(guideSession.messages.last?.sources.map(\.title) == ["Guide's note"])
        #expect(sampleSession.messages.last?.sources.isEmpty == true)
    }

    @Test("Notes handed to on-device chat are cut to fit its context")
    func noteTextIsCapped() {
        let long = Array(repeating: "Counted the golden beads to one thousand", count: 30).joined(separator: " ")
        let excerpt = NotebookToolText.excerpt(long)
        #expect(excerpt.count <= NotebookToolText.noteCharacterLimit + 1)
        #expect(excerpt.hasSuffix("…"))
        #expect(NotebookToolText.excerpt("Short note.\nSecond line.") == "Short note. Second line.")

        let lines = Array(repeating: excerpt, count: 20)
        let kept = NotebookToolText.fitting(lines)
        #expect(!kept.isEmpty && kept.count < 20)
        #expect(kept.reduce(0) { $0 + $1.count + 1 } <= NotebookToolText.replyCharacterLimit)
        // One note longer than the whole limit still comes back.
        #expect(NotebookToolText.fitting([long], limit: 10) == [long])
    }
}
