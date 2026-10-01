import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Holds the model's answer until released.
@MainActor
private final class AnswerGate {
    private var held: CheckedContinuation<Void, Never>?
    private(set) var answered = false
    var isHolding: Bool { held != nil }

    func release() {
        held?.resume()
        held = nil
    }

    func hold() async {
        await withCheckedContinuation { held = $0 }
        answered = true
    }
}

/// Stands in for the model: answers once the gate opens, whichever way the
/// chat asks (today `ChatService` reaches the protocol's non-streaming
/// fallback, which calls `sendConversation`).
private struct HeldAnswerClient: MCPClientProtocol {
    let gate: AnswerGate
    func generateText(prompt: String, temperature: Double) async throws -> String { "" }
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { "{}" }
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?
    ) async throws -> String {
        await gate.hold()
        return "Maya had the golden beads on Monday."
    }
    // swiftlint:disable:next function_parameter_count
    func streamConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        await gate.hold()
        return "Maya had the golden beads on Monday."
    }
}

// Logic-break sweep 2026-09-29, E2. Ask AI's tools read the guide's own
// notebook even in Sample Class, the saved chat was one for both
// classrooms, and New Chat mid-answer brought the old chat back when the
// answer landed. Serialized: `ChatToolContext` is one process-wide value,
// set by whichever chat answered last.
@Suite("Ask AI chat", .serialized)
@MainActor
struct ChatViewModelTests {

    private let stack: CoreDataStack
    private let defaults: UserDefaults

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let name = "ChatViewModelTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
    }

    private func model(_ gate: AnswerGate, sampleClassroom: Bool = false) -> ChatViewModel {
        let model = ChatViewModel()
        model.configure(
            viewContext: stack.viewContext, mcpClient: HeldAnswerClient(gate: gate),
            sampleClassroom: sampleClassroom, defaults: defaults
        )
        return model
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test("New Chat while an answer streams stays new when the answer lands")
    func newChatMidAnswer() async throws {
        let gate = AnswerGate()
        let chat = model(gate)
        chat.inputText = "What did Maya do this week?"
        chat.sendMessage()
        #expect(await waitUntil { gate.isHolding })

        chat.resetSession()
        gate.release()
        #expect(await waitUntil { gate.answered })
        for _ in 0..<50 { await Task.yield() }

        #expect(chat.messages.isEmpty)
        #expect(!chat.isLoading)
        #expect(ChatSession.loadSaved(defaults: defaults) == nil)
    }

    @Test("An answer is saved as the chat of the classroom it was asked in")
    func savedPerClassroom() async throws {
        let gate = AnswerGate()
        let sample = model(gate, sampleClassroom: true)
        sample.inputText = "Who is here today?"
        sample.sendMessage()
        #expect(await waitUntil { gate.isHolding })
        gate.release()
        await sample.waitForSend()

        #expect(ChatSession.loadSaved(sampleClassroom: true, defaults: defaults)?.messages.count == 2)
        #expect(ChatSession.loadSaved(defaults: defaults) == nil)
        // The guide's own chat opens fresh, not on Sample Class's.
        #expect(model(AnswerGate()).messages.isEmpty)
    }

    @Test("The notebook tools read the classroom the chat answers in")
    func toolsReadTheChatsClassroom() async throws {
        let gate = AnswerGate()
        let chat = model(gate, sampleClassroom: true)
        chat.inputText = "Who is here today?"
        chat.sendMessage()
        #expect(await waitUntil { gate.isHolding })
        #expect(ChatToolContext.context === stack.viewContext)
        gate.release()
        await chat.waitForSend()
    }
}
