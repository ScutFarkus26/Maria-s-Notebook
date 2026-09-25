import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Chat answers reach the screen through `StreamingTextThrottle`: the whole
/// answer so far, at most about ten times a second, with whatever is waiting
/// always shown when the stream ends. The saved reply must be exactly today's.
@Suite("Streaming text throttle")
@MainActor
struct StreamingTextThrottleTests {

    private let interval = Duration.milliseconds(100)

    /// Today's accumulation: a delta cut from each cumulative snapshot that
    /// adds a character (LocalModelClient) and appended to the shown text
    /// (ChatViewModel). Returns what the bubble ended on and the reply saved.
    private func legacyPipeline(_ snapshots: [String]) -> (shown: String, reply: String) {
        var emitted = ""
        var shown = ""
        for full in snapshots where full.count > emitted.count {
            shown += String(full.dropFirst(emitted.count))
            emitted = full
        }
        return (shown, emitted)
    }

    /// Snapshots of a reply growing a token at a time, Markdown and all.
    private func snapshots(tokens: Int) -> [String] {
        let words = ["**Ora**", "has", "had", "the", "*Checkerboard*", "—", "twice;", "see", "p. 12.\n", "- a"]
        var text = ""
        return (0..<tokens).map { index in
            text += words[index % words.count] + " "
            return text
        }
    }

    // MARK: - The pacing rule, on synthetic time

    private struct Shown {
        let at: ContinuousClock.Instant
        let text: String
        let isFlush: Bool
    }

    /// Replays chunks arriving every `spacing` for the given texts, firing the
    /// scheduled update whenever its time passes, then ends the stream
    /// `endAfter` past the last chunk and flushes.
    private func replay(
        _ texts: [String], spacing: Duration, endAfter: Duration
    ) -> [Shown] {
        var pacing = StreamingTextThrottle.Pacing(interval: interval)
        var shown: [Shown] = []
        let start = ContinuousClock.now
        var now = start
        func fireDue(until time: ContinuousClock.Instant) {
            while let due = pacing.dueAt, due <= time {
                if let text = pacing.fire(at: due) { shown.append(Shown(at: due, text: text, isFlush: false)) }
            }
        }
        for (index, text) in texts.enumerated() {
            now = start + spacing * index
            fireDue(until: now)
            if let text = pacing.submit(text, at: now) { shown.append(Shown(at: now, text: text, isFlush: false)) }
        }
        let end = now + endAfter
        fireDue(until: end)
        if let text = pacing.flush(at: end) { shown.append(Shown(at: end, text: text, isFlush: true)) }
        return shown
    }

    @Test("A fast stream is shown at most ten times a second, and its last text always")
    func fastStreamIsBounded() throws {
        // 600 chunks, 7 ms apart: 4.2 s of streaming, 143 chunks a second.
        let texts = snapshots(tokens: 600)
        let shown = replay(texts, spacing: .milliseconds(7), endAfter: .milliseconds(3))

        let paced = shown.filter { !$0.isFlush }
        for (earlier, later) in zip(paced, paced.dropFirst()) {
            #expect(later.at - earlier.at >= interval)
        }
        for first in shown.indices {
            let windowEnd = shown[first].at + .seconds(1)
            #expect(shown[first...].prefix { $0.at < windowEnd }.count <= 11)
        }
        #expect(shown.count <= 44)
        #expect(shown.count >= 40)
        #expect(shown.first?.text == texts.first)
        #expect(shown.last?.text == texts.last)
        #expect(shown.last?.text == legacyPipeline(texts).shown)
    }

    @Test("A stream that ends inside a throttle window still shows its last text")
    func endInsideWindowIsFlushed() {
        let shown = replay(["Ora", "Ora has", "Ora has had"], spacing: .milliseconds(20), endAfter: .milliseconds(10))
        #expect(shown.map(\.text) == ["Ora", "Ora has had"])
        #expect(shown.last?.isFlush == true)
    }

    @Test("A slow stream is shown chunk by chunk, as before")
    func slowStreamIsUnthrottled() {
        let texts = snapshots(tokens: 12)
        let shown = replay(texts, spacing: .milliseconds(150), endAfter: .milliseconds(150))
        #expect(shown.map(\.text) == texts)
    }

    @Test("Nothing waiting means the flush shows nothing more")
    func flushWithNothingPending() {
        var pacing = StreamingTextThrottle.Pacing(interval: interval)
        let now = ContinuousClock.now
        #expect(pacing.submit("Ora", at: now) == "Ora")
        #expect(pacing.flush(at: now + .milliseconds(5)) == nil)
        #expect(pacing.dueAt == nil)
    }

    // MARK: - The throttle on the real clock

    private final class Published {
        var texts: [String] = []
    }

    @Test("The scheduled update arrives on its own")
    func scheduledUpdateArrives() async throws {
        let published = Published()
        let throttle = StreamingTextThrottle(interval: .milliseconds(50)) { published.texts.append($0) }

        throttle.submit("Ora")
        throttle.submit("Ora has")
        #expect(published.texts == ["Ora"])
        #expect(throttle.isUpdateScheduled)

        let deadline = ContinuousClock.now + .seconds(10)
        while published.texts.count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(published.texts == ["Ora", "Ora has"])
        #expect(!throttle.isUpdateScheduled)
    }

    @Test("A flush shows what is waiting at once and leaves nothing scheduled")
    func flushCancelsTheScheduledUpdate() {
        let published = Published()
        let throttle = StreamingTextThrottle(interval: .seconds(60)) { published.texts.append($0) }

        throttle.submit("Ora")
        throttle.submit("Ora has")
        throttle.submit("Ora has had")
        #expect(throttle.isUpdateScheduled)
        throttle.flush()
        #expect(!throttle.isUpdateScheduled)
        #expect(published.texts == ["Ora", "Ora has had"])
    }

    @Test("A burst of chunks shows the first at once and the last on flush — today's final text")
    func burstThenFlush() {
        let published = Published()
        let throttle = StreamingTextThrottle { published.texts.append($0) }
        let texts = snapshots(tokens: 500)
        for text in texts { throttle.submit(text) }
        throttle.flush()

        #expect(published.texts.count == 2)
        #expect(published.texts.first == texts.first)
        #expect(published.texts.last == legacyPipeline(texts).shown)
        #expect(!throttle.isUpdateScheduled)
    }

    // MARK: - The reply through ChatService

    /// A client whose conversation answer is fixed. Its streaming method
    /// records a call: ChatService's call omits `timeout`, so it resolves to
    /// the protocol's non-streaming fallback and never reaches this.
    private final class FixedAnswerClient: MCPClientProtocol {
        let answer: String
        var streamingCalls = 0

        init(answer: String) {
            self.answer = answer
        }

        func generateText(prompt: String, temperature: Double) async throws -> String { answer }
        func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { "{}" }
        // swiftlint:disable:next function_parameter_count
        func sendConversation(
            messages: [[String: String]], systemMessage: String?, temperature: Double,
            maxTokens: Int, model: String?, timeout: TimeInterval?
        ) async throws -> String { answer }
        // swiftlint:disable:next function_parameter_count
        func streamConversation(
            messages: [[String: String]], systemMessage: String?, temperature: Double,
            maxTokens: Int, model: String?, timeout: TimeInterval?,
            onText: @escaping @MainActor @Sendable (String) -> Void
        ) async throws -> String {
            streamingCalls += 1
            return answer
        }
    }

    @Test("The saved reply is the model's answer byte for byte, handed over whole")
    func replyIsUnchanged() async throws {
        let answer = "**Ora** has had the *Checkerboard* twice — café, 👍🏽, 🇺🇸.\n- next: Racks and Tubes"
        let client = FixedAnswerClient(answer: answer)
        let service = ChatService(modelContext: try CoreDataTestHelpers.makeContext(), mcpClient: client)
        var session = service.startSession()
        let published = Published()
        let throttle = StreamingTextThrottle { published.texts.append($0) }

        let reply = try await service.sendMessageStreaming("What has Ora had?", session: &session) { answerSoFar in
            throttle.submit(answerSoFar)
        }
        throttle.flush()

        #expect(reply == answer)
        #expect(session.messages.last?.content == answer)
        #expect(session.messages.last?.role == .assistant)
        #expect(published.texts == [answer])
        #expect(client.streamingCalls == 0)
    }
}
