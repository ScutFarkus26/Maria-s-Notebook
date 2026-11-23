import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// State layer review 2026-11-22, B7: a second follow-up asked while the
/// planning assistant is still answering the first is ignored, as the text
/// field already is. Each call used to copy the same session, so whichever
/// reply came last wrote over the other's question and answer.

/// Answers every request with an empty plan, and can hold replies open until
/// told to let them go.
@MainActor
private final class HeldReplyClient: MCPClientProtocol {
    private(set) var requests = 0
    var holdsReplies = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func release() {
        holdsReplies = false
        let held = waiting
        waiting = []
        held.forEach { $0.resume() }
    }

    private func reply() async -> String {
        requests += 1
        if holdsReplies {
            await withCheckedContinuation { waiting.append($0) }
        }
        return #"{"recommendations": [], "summary": "Because it comes next in her sequence."}"#
    }

    func generateText(prompt: String, temperature: Double) async throws -> String { await reply() }
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { await reply() }
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?
    ) async throws -> String { await reply() }
}

@Suite("Lesson planning follow-up guard (state layer B7)")
@MainActor
struct LessonPlanningFollowUpGuardTests {
    private struct TimedOut: Error {}

    /// Waits, a few milliseconds at a time, until `condition` holds.
    private func wait(until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("A second follow-up asked while the first is being answered is ignored")
    func secondFollowUpDuringAReplyIsIgnored() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Cohen")
        CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Mathematics", sequence: "Decimal System")
        try context.save()
        let studentID = try #require(student.id)

        let client = HeldReplyClient()
        let viewModel = LessonPlanningViewModel(mode: .singleStudent(studentID))
        viewModel.selectedDepth = .quick
        viewModel.configure(context: context, mcpClient: client, saveCoordinator: SaveCoordinator())

        // A plan first: follow-ups need its session.
        viewModel.startPlanning()
        try await wait { viewModel.currentSession != nil && !viewModel.isLoading }
        let planningRequests = client.requests
        func questions() -> [String] {
            viewModel.messages.filter { $0.role == .teacher }.map(\.content)
        }

        // The first follow-up reaches the model, which takes its time.
        client.holdsReplies = true
        viewModel.sendMessage("Why this one?")
        try await wait { client.requests == planningRequests + 1 }
        #expect(viewModel.isLoading)

        // A "Why?" tapped meanwhile.
        viewModel.sendMessage("Why not another?")
        #expect(questions() == ["Why this one?"])
        // Long enough for a second request to reach the model, had one started.
        try await Task.sleep(for: .milliseconds(100))
        #expect(client.requests == planningRequests + 1, "the second follow-up asked the model too")
        #expect(viewModel.isLoading, "the spinner stays until the held reply arrives")

        client.release()
        try await wait { !viewModel.isLoading }
        #expect(questions() == ["Why this one?"])
        #expect(viewModel.currentSession?.messages.filter { $0.role == .teacher }.count == 1)
        // The plan's own summary, then the one answer.
        #expect(viewModel.messages.filter { $0.role == .assistant }.count == 2)
        #expect(client.requests == planningRequests + 1)
    }
}
