import Foundation
import os
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, agent AI (#15, #16), and the router's cancellation
/// rule (2026-10-11 #53): how the model clients read an answer and keep to a
/// time limit.
@Suite("Model answers and limits (10-17 AI)", .serialized)
@MainActor
struct ModelAnswerFix1017AI {

    /// A model that answers a plain request with `answer`, counting its calls.
    private final class FakeModel: RoutableModelClient {
        let isAvailable = true
        let unavailabilityReason = ""
        private(set) var calls = 0
        private let answer: () async throws -> String

        init(answer: @escaping () async throws -> String) {
            self.answer = answer
        }

        func generateText(prompt: String, temperature: Double) async throws -> String {
            calls += 1
            return try await answer()
        }

        func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { "{}" }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: #15

    @Test("JSON wrapped in a code fence or a sentence is still read")
    func fencedJSONIsRead() throws {
        #expect(ModelJSONText.validated("{\"a\": 1}") == "{\"a\": 1}")
        #expect(ModelJSONText.validated("```json\n{\"a\": 1}\n```") == "{\"a\": 1}")
        #expect(ModelJSONText.validated("```\n[1, 2]\n```\n") == "[1, 2]")
        #expect(ModelJSONText.validated("Here are the matches:\n{\"lessons\": [\"Golden Beads\"]}\nHope that helps!")
            == "{\"lessons\": [\"Golden Beads\"]}")
        #expect(ModelJSONText.validated("Sure: [{\"x\": {\"y\": 2}}] done") == "[{\"x\": {\"y\": 2}}]")
        // Still nothing usable: no JSON at all, or a broken object.
        #expect(ModelJSONText.validated("I couldn't find any lessons.") == nil)
        #expect(ModelJSONText.validated("```json\n{\"a\": \n```") == nil)
    }

    // MARK: #16

    /// Whether the slow request saw its cancellation.
    nonisolated private final class Cancelled: Sendable {
        let flag = OSAllocatedUnfairLock(initialState: false)
    }

    @Test("A request past the caller's time limit stops with a plain message and is cancelled")
    func timeoutIsHonored() async throws {
        let cancelled = Cancelled()
        let started = ContinuousClock.now
        let error = await #expect(throws: LocalModelError.self) {
            _ = try await ModelRequestTimeout.run(limit: 0.1) {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    cancelled.flag.withLock { $0 = true }
                    throw error
                }
                return "Too late."
            }
        }
        #expect(error?.errorDescription == AppleIntelligenceMessages.timedOut)
        #expect(ContinuousClock.now - started < .seconds(10))
        // The losing request is cancelled, not waited for (review (b) #7),
        // so its cancellation lands a moment after the answer.
        #expect(await waitUntil { cancelled.flag.withLock { $0 } })
    }

    @Test("A request inside its time limit, or with none, answers as before")
    func withinTheLimitAnswers() async throws {
        #expect(try await ModelRequestTimeout.run(limit: 10) { "On time." } == "On time.")
        #expect(try await ModelRequestTimeout.run(limit: nil) { "No limit." } == "No limit.")
    }

    // MARK: #53 (routing)

    @Test("A cancelled request isn't sent again to Private Cloud")
    func cancelledIsNotRetried() async throws {
        let local = FakeModel {
            try await Task.sleep(for: .seconds(30))
            return "Too late."
        }
        let cloud = FakeModel { "From Private Cloud." }

        let work: (any MCPClientProtocol) async throws -> String = {
            try await $0.generateText(prompt: "How is Etty D doing?", temperature: 0.7)
        }
        let send = Task {
            try await AIClientRouter.route(local: local, cloud: { cloud }, cloudAllowed: true, work)
        }
        while local.calls == 0 { await Task.yield() }
        send.cancel()
        let result = await send.result

        #expect(cloud.calls == 0)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}
