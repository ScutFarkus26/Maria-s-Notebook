import Foundation
import Testing
@testable import CosmicDaybook

/// Calls through `MCPClientProtocol` must reach the client's own
/// implementation. The protocol extension's fallbacks are for clients that
/// have none, never a detour for clients that do: a fallback with defaulted
/// parameters would win any call that leaves one out, statically, and the
/// client's streaming or system-prompt handling would never run.
@Suite("MCP client dispatch")
@MainActor
struct MCPClientDispatchTests {

    @MainActor
    private final class Recorder {
        var texts: [String] = []
    }

    /// Streams two snapshots and answers something else when asked without
    /// streaming, so the two paths can be told apart.
    private final class StreamingClient: MCPClientProtocol {
        var sendCalls = 0
        var streamCalls = 0

        func generateText(prompt: String, temperature: Double) async throws -> String { "text" }
        func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { "{}" }
        // swiftlint:disable:next function_parameter_count
        func sendConversation(
            messages: [[String: String]], systemMessage: String?, temperature: Double,
            maxTokens: Int, model: String?, timeout: TimeInterval?
        ) async throws -> String {
            sendCalls += 1
            return "whole answer, not streamed"
        }
        // swiftlint:disable:next function_parameter_count
        func streamConversation(
            messages: [[String: String]], systemMessage: String?, temperature: Double,
            maxTokens: Int, model: String?, timeout: TimeInterval?,
            onText: @escaping @MainActor @Sendable (String) -> Void
        ) async throws -> String {
            streamCalls += 1
            onText("Ora has")
            onText("Ora has had the Checkerboard")
            return "Ora has had the Checkerboard"
        }
    }

    /// Shaped like AIClientRouter: the two-argument and full forms only,
    /// recording what the full form was handed.
    private final class FullFormClient: MCPClientProtocol {
        var textSystemMessage: String?
        var textMaxTokens: Int?
        var jsonSystemMessage: String?
        var jsonMaxTokens: Int?

        func generateText(prompt: String, temperature: Double) async throws -> String {
            try await generateText(
                prompt: prompt, systemMessage: nil, temperature: temperature,
                maxTokens: nil, model: nil, timeout: nil
            )
        }
        // swiftlint:disable:next function_parameter_count
        func generateText(
            prompt: String, systemMessage: String?, temperature: Double,
            maxTokens: Int?, model: String?, timeout: TimeInterval?
        ) async throws -> String {
            textSystemMessage = systemMessage
            textMaxTokens = maxTokens
            return "text"
        }
        func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
            try await generateStructuredJSON(
                prompt: prompt, systemMessage: nil, temperature: temperature,
                maxTokens: nil, model: nil, timeout: nil
            )
        }
        // swiftlint:disable:next function_parameter_count
        func generateStructuredJSON(
            prompt: String, systemMessage: String?, temperature: Double,
            maxTokens: Int?, model: String?, timeout: TimeInterval?
        ) async throws -> String {
            jsonSystemMessage = systemMessage
            jsonMaxTokens = maxTokens
            return "{}"
        }
    }

    /// Only the two required short forms: every other call lands on the
    /// protocol's fallbacks.
    private final class ShortFormClient: MCPClientProtocol {
        var textPrompts: [String] = []

        func generateText(prompt: String, temperature: Double) async throws -> String {
            textPrompts.append(prompt)
            return "short answer"
        }
        func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { "{\"ok\":true}" }
    }

    // MARK: - Ask AI

    @Test("Ask AI streams through the client's own streamConversation")
    func chatServiceStreams() async throws {
        let client = StreamingClient()
        let service = ChatService(modelContext: try CoreDataTestHelpers.makeContext(), mcpClient: client)
        var session = service.startSession()
        let recorder = Recorder()

        let reply = try await service.sendMessageStreaming("What has Ora had?", session: &session) { answerSoFar in
            recorder.texts.append(answerSoFar)
        }

        #expect(client.streamCalls == 1)
        #expect(client.sendCalls == 0)
        #expect(recorder.texts == ["Ora has", "Ora has had the Checkerboard"])
        #expect(reply == "Ora has had the Checkerboard")
        #expect(session.messages.last?.content == "Ora has had the Checkerboard")
    }

    // MARK: - The system-prompt forms

    @Test("generateText with a system message reaches the client's full form")
    func textSystemMessageReachesClient() async throws {
        let recording = FullFormClient()
        let client: any MCPClientProtocol = recording

        _ = try await client.generateText(
            prompt: "Draft", systemMessage: "You write parent reports.",
            temperature: 0.6, maxTokens: 600
        )

        #expect(recording.textSystemMessage == "You write parent reports.")
        #expect(recording.textMaxTokens == 600)
    }

    @Test("generateStructuredJSON with a system message reaches the client's full form")
    func jsonSystemMessageReachesClient() async throws {
        let recording = FullFormClient()
        let client: any MCPClientProtocol = recording

        _ = try await client.generateStructuredJSON(
            prompt: "Analyze", systemMessage: "You analyze meetings.",
            temperature: 0.3, maxTokens: 2048
        )

        #expect(recording.jsonSystemMessage == "You analyze meetings.")
        #expect(recording.jsonMaxTokens == 2048)
    }

    // MARK: - The fallbacks

    @Test("A client with only the short forms still answers every form")
    func shortFormClientAnswersEverything() async throws {
        let shortForm = ShortFormClient()
        let client: any MCPClientProtocol = shortForm
        let recorder = Recorder()

        let four = try await client.generateText(
            prompt: "a", systemMessage: "s", temperature: 0.5, maxTokens: 10
        )
        let six = try await client.generateText(
            prompt: "b", systemMessage: "s", temperature: 0.5, maxTokens: 10, model: nil, timeout: nil
        )
        let json = try await client.generateStructuredJSON(
            prompt: "c", systemMessage: "s", temperature: 0.5, maxTokens: 10, model: nil, timeout: nil
        )
        let streamed = try await client.streamConversation(
            messages: [["role": "user", "content": "hi"]], systemMessage: nil,
            temperature: 0.7, maxTokens: 100, model: nil, timeout: nil
        ) { answerSoFar in
            recorder.texts.append(answerSoFar)
        }

        #expect(four == "short answer")
        #expect(six == "short answer")
        #expect(json == "{\"ok\":true}")
        #expect(streamed == "short answer")
        #expect(recorder.texts == ["short answer"])
        #expect(shortForm.textPrompts == ["a", "b", "user: hi"])
    }
}
