import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, review (b) #7: the time limit waited for a model
/// that ignored cancellation. `ModelRequestTimeout` ran the request and its
/// timer in a task group, which waits for every child, so "took too long"
/// came only when the model finally stopped; and Private Cloud Compute's
/// retry got the whole limit again. Also #8, Parsha's "Until then" line.
@Suite("Model time limits (Fix1017 review b)")
@MainActor
struct ModelTimeoutFix1017ReviewB {

    /// A model that ignores cancellation: its answer comes from a task the
    /// caller's cancellation never reaches.
    private static func stubbornAnswer(after delay: Duration) async -> String {
        await Task.detached {
            try? await Task.sleep(for: delay)
            return "Too late."
        }.value
    }

    @Test("#7 A request that ignores cancellation still stops at the time limit")
    func limitHoldsWhenTheModelIgnoresCancellation() async throws {
        let started = ContinuousClock.now
        let error = await #expect(throws: LocalModelError.self) {
            _ = try await ModelRequestTimeout.run(limit: 0.2) {
                await Self.stubbornAnswer(after: .seconds(5))
            }
        }
        #expect(error?.errorDescription == AppleIntelligenceMessages.timedOut)
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test("#7 Cancelling the caller stops the wait at once, even when the model ignores it")
    func callerCancellationStopsTheWait() async throws {
        let started = ContinuousClock.now
        let waiting = Task {
            try await ModelRequestTimeout.run(limit: 30) {
                await Self.stubbornAnswer(after: .seconds(5))
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        waiting.cancel()
        let result = await waiting.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    // MARK: - #7 Private Cloud gets only the time left

    @Test("#7 A deadline gives each attempt the time left, and none once it's past")
    func deadlineCountsDown() throws {
        let start = ContinuousClock.now
        let deadline = AIClientRouter.Deadline(limit: 10, from: start)
        let left = try #require(try deadline.remaining(at: start.advanced(by: .seconds(4))))
        #expect(abs(left - 6) < 0.001)
        let error = #expect(throws: LocalModelError.self) {
            try deadline.remaining(at: start.advanced(by: .seconds(11)))
        }
        #expect(error?.errorDescription == AppleIntelligenceMessages.timedOut)
        #expect(try AIClientRouter.Deadline(limit: nil).remaining() == nil)
        #expect(try AIClientRouter.Deadline(limit: 0).remaining() == nil)
    }

    private final class FakeModel: RoutableModelClient {
        let isAvailable = true
        let unavailabilityReason = ""
        func generateText(prompt: String, temperature: Double) async throws -> String { "" }
        func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { "{}" }
    }

    @Test("#7 After a slow on-device failure, Private Cloud's limit is what's left")
    func cloudRetryGetsTimeLeft() async throws {
        let local = FakeModel()
        let cloud = FakeModel()
        let deadline = AIClientRouter.Deadline(limit: 1)
        var limits: [TimeInterval?] = []
        let attempt: (any MCPClientProtocol) async throws -> String = { client in
            limits.append(try deadline.remaining())
            if (client as AnyObject) === local {
                try await Task.sleep(for: .milliseconds(400))
                throw LocalModelError.generationFailed(AppleIntelligenceMessages.busy)
            }
            return "From Private Cloud."
        }
        let answer = try await AIClientRouter.route(local: local, cloud: { cloud }, cloudAllowed: true, attempt)
        #expect(answer == "From Private Cloud.")
        #expect(limits.count == 2)
        let cloudLimit = try #require(limits.last ?? nil)
        #expect(cloudLimit < 0.7)
    }

    // MARK: - #8 "Until then" only when it will pass

    @Test("#8 \"Until then\" follows only Apple Intelligence off or still getting ready")
    func untilThenOnlyWhenItWillPass() {
        let off = "suggestions are off"
        #expect(AIClientRouter.unavailabilityNotice(off, reason: AppleIntelligenceMessages.turnOn)
            == "\(AppleIntelligenceMessages.turnOn) Until then, suggestions are off.")
        #expect(AIClientRouter.unavailabilityNotice(off, reason: AppleIntelligenceMessages.stillGettingReady)
            .hasSuffix("Until then, suggestions are off."))
        for lasting in [
            AppleIntelligenceMessages.deviceNotEligible,
            AppleIntelligenceMessages.notInThisVersion,
            AppleIntelligenceMessages.notAvailable
        ] {
            let notice = AIClientRouter.unavailabilityNotice(off, reason: lasting)
            #expect(notice == "\(lasting) Suggestions are off.")
            #expect(!notice.contains("Until then"))
        }
    }
}
