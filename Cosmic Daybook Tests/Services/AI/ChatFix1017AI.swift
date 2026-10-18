import CoreData
import Foundation
import os
import Testing
@testable import CosmicDaybook

/// A fake model's answer: the tools it was given and where to stream text.
private typealias StreamingAnswer =
    (ChatToolContext, @escaping @MainActor @Sendable (String) -> Void) async throws -> String

/// Bug hunt 2026-10-17, agent AI: Ask AI and the on-device model (#9, #11,
/// #15, #16).
@Suite("Ask AI fixes (10-17 AI)", .serialized)
@MainActor
struct ChatFix1017AI {

    private let stack: CoreDataStack
    private let defaults: UserDefaults

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let name = "ChatFix1017AI.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
    }

    /// A model that answers by running `answer`, counting its calls.
    private final class FakeModel: RoutableModelClient {
        let isAvailable = true
        let unavailabilityReason = ""
        private(set) var calls = 0
        private let answer: StreamingAnswer

        init(answer: @escaping StreamingAnswer) {
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
            return try await answer(tools, onText)
        }
    }

    /// Holds the model's answer until released.
    private final class Gate {
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

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func chat(_ client: any MCPClientProtocol) -> ChatViewModel {
        let model = ChatViewModel()
        model.configure(viewContext: stack.viewContext, mcpClient: client, defaults: defaults)
        return model
    }

    // MARK: #11

    @Test("New Chat mid-answer: the old answer's waiting update never reaches the new chat")
    func throttledUpdateAfterNewChatIsDropped() async throws {
        let gate = Gate()
        let client = FakeModel { _, onText in
            // The first text shows at once; the second waits ~100 ms for the
            // throttle's next update.
            onText("Maya had")
            onText("Maya had the golden beads")
            await gate.hold()
            return "Maya had the golden beads on Monday."
        }
        let model = chat(client)
        model.inputText = "What did Maya do this week?"
        model.sendMessage()
        #expect(await waitUntil { gate.isHolding })

        model.resetSession()
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.streamingContent == nil)

        gate.release()
        #expect(await waitUntil { gate.answered })
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.streamingContent == nil)
        #expect(model.messages.isEmpty)
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

    // MARK: #9's message

    @Test("The unfinished-answer line names everything the tools saved")
    func unfinishedAnswerMessage() {
        #expect(ChatWrite.unfinishedAnswerMessage(for: []) == nil)
        #expect(ChatWrite.unfinishedAnswerMessage(for: [.followUpAdded])
            == "The follow-up was added, but the answer couldn't be finished.")
        #expect(ChatWrite.unfinishedAnswerMessage(for: [.meeting, .meeting, .followUpResolved])
            == "2 meetings were recorded and the follow-up was marked done, but the answer couldn't be finished.")
    }
}

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)

/// #9: a write tool ran, then the answer failed.
@Suite("Ask AI writes then fails (10-17 AI #9)", .serialized)
@MainActor
struct ChatWriteThenFailFix1017AI {

    private let stack: CoreDataStack
    private let defaults: UserDefaults

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let name = "ChatWriteThenFailFix1017AI.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        CoreDataTestHelpers.seedStudent(in: stack.viewContext, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(stack.viewContext)
    }

    private final class FakeModel: RoutableModelClient {
        let isAvailable = true
        let unavailabilityReason = ""
        private(set) var calls = 0
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
            return try await answer(tools)
        }
    }

    /// Runs Ask AI's own record-meeting tool, built for this answer.
    private static func recordMeeting(_ tools: ChatToolContext, reflection: String) async throws -> String {
        let tool = try #require(
            NotebookTools.meetingTools(toolContext: tools).compactMap { $0 as? RecordStudentMeetingTool }.first
        )
        return try await tool.call(arguments: .init(
            student: "Ora", date: "", reflection: reflection,
            lessonRequests: "", guideNotes: "", goals: []
        ))
    }

    /// The on-device model records the meeting, then its answer overflows.
    private func recordsThenOverflows() -> FakeModel {
        FakeModel { tools in
            _ = try await Self.recordMeeting(tools, reflection: "Working through the Skyscrapers drawers.")
            throw LocalModelError.contextTooLarge
        }
    }

    private var meetingCount: Int {
        stack.viewContext.safeFetch(CDFetchRequest(CDStudentMeeting.self)).count
    }

    @Test("After a write, a failed on-device answer isn't sent again to Private Cloud")
    func noFallbackAfterAWrite() async throws {
        let tools = ChatToolContext(stack.viewContext)
        let local = recordsThenOverflows()
        let cloud = FakeModel { _ in "I can't record meetings." }

        await #expect(throws: (any Error).self) {
            _ = try await AIClientRouter.streamChat(
                local: local, cloud: { cloud }, cloudAllowed: true,
                messages: [["role": "user", "content": "Record a meeting with Ora."]], systemMessage: nil,
                temperature: 0.7, maxTokens: 256, tools: tools, onText: { _ in }
            )
        }
        #expect(local.calls == 1)
        #expect(cloud.calls == 0)
        #expect(meetingCount == 1)
    }

    @Test("A write tool that refused (nothing saved) still lets Private Cloud answer")
    func refusedWriteStillFallsBack() async throws {
        let tools = ChatToolContext(stack.viewContext)
        let local = FakeModel { tools in
            _ = try await Self.recordMeeting(tools, reflection: "")
            throw LocalModelError.contextTooLarge
        }
        let cloud = FakeModel { _ in "From Private Cloud." }

        let answer = try await AIClientRouter.streamChat(
            local: local, cloud: { cloud }, cloudAllowed: true,
            messages: [["role": "user", "content": "Record a meeting with Ora."]], systemMessage: nil,
            temperature: 0.7, maxTokens: 256, tools: tools, onText: { _ in }
        )
        #expect(answer == "From Private Cloud.")
        #expect(cloud.calls == 1)
        #expect(meetingCount == 0)
    }

    @Test("A meeting recorded before the answer failed keeps the exchange and says so")
    func chatKeepsTheExchange() async throws {
        let model = ChatViewModel()
        model.configure(viewContext: stack.viewContext, mcpClient: recordsThenOverflows(), defaults: defaults)
        model.inputText = "Record a meeting with Ora: working through the Skyscrapers drawers."
        model.sendMessage()
        await model.waitForSend()

        #expect(meetingCount == 1)
        // The question isn't put back to be sent again (a second meeting).
        #expect(model.inputText.isEmpty)
        #expect(model.messages.count == 2)
        let reply = try #require(model.messages.last)
        #expect(reply.role == .assistant)
        #expect(reply.content == "The meeting was recorded, but the answer couldn't be finished.")
        #expect(ChatSession.loadSaved(defaults: defaults)?.messages.count == 2)
    }
}

#endif
