import Foundation
import Testing
@testable import CosmicDaybook

/// Calls through `MCPClientProtocol` must reach the client's own
/// implementation. The protocol extension's fallbacks are for clients that
/// have none, never a detour for clients that do: a fallback with defaulted
/// parameters would win any call that leaves one out, statically, and the
/// client's system-prompt handling would never run.
@Suite("MCP client dispatch")
@MainActor
struct MCPClientDispatchTests {

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
                maxTokens: nil, timeout: nil
            )
        }
        func generateText(
            prompt: String, systemMessage: String?, temperature: Double,
            maxTokens: Int?, timeout: TimeInterval?
        ) async throws -> String {
            textSystemMessage = systemMessage
            textMaxTokens = maxTokens
            return "text"
        }
        func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
            try await generateStructuredJSON(
                prompt: prompt, systemMessage: nil, temperature: temperature,
                maxTokens: nil, timeout: nil
            )
        }
        func generateStructuredJSON(
            prompt: String, systemMessage: String?, temperature: Double,
            maxTokens: Int?, timeout: TimeInterval?
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

        let four = try await client.generateText(
            prompt: "a", systemMessage: "s", temperature: 0.5, maxTokens: 10
        )
        let six = try await client.generateText(
            prompt: "b", systemMessage: "s", temperature: 0.5, maxTokens: 10, timeout: nil
        )
        let json = try await client.generateStructuredJSON(
            prompt: "c", systemMessage: "s", temperature: 0.5, maxTokens: 10, timeout: nil
        )
        let conversation = try await client.sendConversation(
            messages: [["role": "user", "content": "hi"]], systemMessage: nil,
            temperature: 0.7, maxTokens: 100, timeout: nil
        )

        #expect(four == "short answer")
        #expect(six == "short answer")
        #expect(json == "{\"ok\":true}")
        #expect(conversation == "short answer")
        #expect(shortForm.textPrompts == ["a", "b", "user: hi"])
    }
}
