import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-05 (#62): the launch pass dedups and repairs on a context
// of its own, and a post-import pass could run beside it on another, folding
// the same rows from a view the other was changing. The launch pass now holds
// the coordinator for as long as it runs.

@Suite("Deduplication coordinator held by the launch pass")
@MainActor
struct DeduplicationCoordinatorHoldTests {

    private func waitUntil(
        timeout: Duration = .seconds(30),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test("A cycle that fires while the launch pass holds the coordinator runs after it, with its scope")
    func cycleWaitsForTheHolder() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let recorder = HeldPassRecorder()
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(1)) { scope, _, _ in
            await recorder.run(scope)
        }
        coordinator.persistentContainer = stack.container

        await coordinator.holdingPasses {
            coordinator.requestDeduplication(insertedEntities: ["Note"])
            #expect(await waitUntil { coordinator.cycleCount == 1 })
            // The cycle fired, and found the coordinator held.
            #expect(recorder.started.isEmpty)
        }

        #expect(await waitUntil { recorder.started.count == 1 })
        recorder.releaseAll()
        #expect(recorder.started == [DeduplicationScope(insertedEntities: ["Note"])])
    }

    @Test("The launch pass waits for a post-import pass already running")
    func holderWaitsForARunningPass() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let recorder = HeldPassRecorder()
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(1)) { scope, _, _ in
            await recorder.run(scope)
        }
        coordinator.persistentContainer = stack.container
        coordinator.requestDeduplication()
        #expect(await waitUntil { recorder.started.count == 1 })

        let launchPass = Task { @MainActor in
            await coordinator.holdingPasses { recorder.launchPassRan = true }
        }
        for _ in 0..<50 { await Task.yield() }
        #expect(!recorder.launchPassRan)

        recorder.releaseAll()
        await launchPass.value
        #expect(recorder.launchPassRan)
    }
}

/// Records each pass's scope and holds it open until released, and whether
/// the launch pass's work has run.
@MainActor
private final class HeldPassRecorder {
    private(set) var started: [DeduplicationScope] = []
    var launchPassRan = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func run(_ scope: DeduplicationScope) async {
        started.append(scope)
        await withCheckedContinuation { waiting.append($0) }
    }

    func releaseAll() {
        let held = waiting
        waiting = []
        held.forEach { $0.resume() }
    }
}
