import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// One attach that never returns mustn't hold up filing until the next launch
/// (2026-10-05 sync hunt, #11a), and mustn't let a second pass share beside
/// it either: the guard stops waiting, the lock stays held until the call
/// returns, and setup says so rather than queue behind it.
@Suite("Classroom share attach timeouts", .timeLimit(.minutes(1)))
@MainActor
struct ClassroomShareAttachTimeoutTests {

    private func makeGuard(lock: ClassroomShareAttachLock) throws -> (SharedStoreOrphanGuard, String) {
        let defaults = try #require(UserDefaults(suiteName: "attach-timeout-\(UUID().uuidString)"))
        let context = try CoreDataTestHelpers.makeContext()
        let day = CDNonSchoolDay(context: context)
        day.date = Date()
        #expect(context.safeSave())
        let guardian = SharedStoreOrphanGuard(defaults: defaults)
        guardian.attachLock = lock
        guardian.attachPassTimeout = .milliseconds(100)
        guardian.enqueue([day.objectID])
        return (guardian, day.objectID.uriRepresentation().absoluteString)
    }

    /// Waits up to `limit` for `condition`.
    private func eventually(_ limit: Duration = .seconds(3), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("A pass that never returns frees the guard, keeps the lock and leaves its records listed")
    func timedOutPassFreesTheGuard() async throws {
        let lock = ClassroomShareAttachLock()
        let (guardian, uri) = try makeGuard(lock: lock)
        let gate = Gate()
        let seen = Seen()

        await guardian.attachWaiting { taken in
            seen.taken = taken.map(\.uri)
            await gate.wait()
        }
        // The guard stopped waiting; the pass still holds the lock.
        #expect(seen.taken == [uri])
        #expect(lock.isHeld)
        #expect(lock.holderIsStuck)
        #expect(guardian.pendingURIs == [uri])

        // The next attempt finds it stuck and leaves at once, running nothing.
        await guardian.attachWaiting { _ in seen.secondRan = true }
        #expect(!seen.secondRan)
        #expect(guardian.pendingURIs == [uri])

        // The late call returns: the lock is free again.
        gate.open()
        try await eventually { !lock.isHeld }
        #expect(!lock.isHeld)
        #expect(!lock.holderIsStuck)
    }

    @Test("A pass that returns in time releases the lock, never marked stuck")
    func passInTimeReleases() async throws {
        let lock = ClassroomShareAttachLock()
        let (guardian, uri) = try makeGuard(lock: lock)
        let seen = Seen()
        guardian.attachPassTimeout = .seconds(30)

        await guardian.attachWaiting { taken in seen.taken = taken.map(\.uri) }
        #expect(seen.taken == [uri])
        #expect(!lock.isHeld)
        #expect(!lock.holderIsStuck)
    }

    @Test("Setup gives up behind a stuck pass, now or while it waits; the one-time step waits its turn")
    func setupRefusesWhileStuck() async throws {
        let lock = ClassroomShareAttachLock()
        let gate = Gate()
        let seen = Seen()
        await lock.acquire()

        // Queued behind a pass that is still working.
        let queuedSetup = Task { @MainActor in await lock.runUnlessStuck { "set up" } }
        try await Task.sleep(for: .milliseconds(30))
        let returned = await lock.hand(
            to: { await gate.wait() },
            waitingAtMost: .milliseconds(100),
            afterStuck: { seen.lateReturns += 1 }
        )
        #expect(!returned)
        #expect(await queuedSetup.value == nil)
        // Asked while it's stuck.
        #expect(await lock.runUnlessStuck { "set up" } == nil)

        // A plain waiter (the Mac's one-time attendance step) waits until the call returns.
        let catchUp = Task { @MainActor in await lock.run { seen.order.append("catch-up") } }
        try await Task.sleep(for: .milliseconds(50))
        #expect(seen.order.isEmpty)
        seen.order.append("late return")
        gate.open()
        await catchUp.value
        #expect(seen.order == ["late return", "catch-up"])
        #expect(seen.lateReturns == 1)
        #expect(!lock.isHeld)
        #expect(await lock.runUnlessStuck { "set up" } == "set up")
    }
}

/// Holds a stand-in attach until the test lets it return.
@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// What the stand-in passes saw.
@MainActor
private final class Seen {
    var taken: [String] = []
    var secondRan = false
    var lateReturns = 0
    var order: [String] = []
}
