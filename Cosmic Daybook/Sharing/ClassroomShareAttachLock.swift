import Foundation

/// Held by everything on this device that puts records into the classroom
/// share: Set Up Classroom Sharing (and "Add them to the share", which runs it
/// again), the Mac's one-time "Add this year's attendance to the share", and
/// `SharedStoreOrphanGuard`'s passes. Two at once could each find the same
/// record unshared and ask CloudKit to share it twice, which fails; on
/// 2026-09-27 sharing an already-shared record stopped the export for the
/// session. Waiters go in the order they asked.
///
/// A guard pass can outlive the time it's given (`hand(to:waitingAtMost:)`):
/// `container.share(_:to:)` can block for good, and nothing can cancel it. The
/// lock then stays held until that call returns, however late, and is marked
/// stuck meanwhile, so callers that would rather say so than wait
/// (`runUnlessStuck`, the guard's next pass) don't queue behind it.
@MainActor
final class ClassroomShareAttachLock {
    static let shared = ClassroomShareAttachLock()

    private(set) var isHeld = false
    /// The pass holding the lock outlived its time limit and may never return.
    /// Cleared when it lets go.
    private(set) var holderIsStuck = false

    private struct Waiter {
        let continuation: CheckedContinuation<Bool, Never>
        /// Leaves the line, empty-handed, if the holder is marked stuck.
        let givesUpIfStuck: Bool
    }
    private var waiters: [Waiter] = []

    /// Waits for the lock however long it is held.
    func acquire() async {
        _ = await wait(givingUpIfStuck: false)
    }

    /// Takes the lock, waiting behind a holder that is working, but not behind
    /// one that is stuck (now or while this waits). False when it gave up.
    func acquireUnlessStuck() async -> Bool {
        guard !holderIsStuck else { return false }
        return await wait(givingUpIfStuck: true)
    }

    private func wait(givingUpIfStuck: Bool) async -> Bool {
        guard isHeld else {
            isHeld = true
            return true
        }
        // `release` hands the lock over still held.
        return await withCheckedContinuation { continuation in
            waiters.append(Waiter(continuation: continuation, givesUpIfStuck: givingUpIfStuck))
        }
    }

    func release() {
        holderIsStuck = false
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }
        waiters.removeFirst().continuation.resume(returning: true)
    }

    /// Runs `work` holding the lock.
    func run<T>(_ work: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await work()
    }

    /// Runs `work` holding the lock, unless a stuck pass holds it: then nil,
    /// without running `work`.
    func runUnlessStuck<T>(_ work: () async throws -> T) async rethrows -> T? {
        guard await acquireUnlessStuck() else { return nil }
        defer { release() }
        return try await work()
    }

    /// Hands the lock, which the caller holds, to `work`; it is released when
    /// `work` returns. Waits for that at most `limit`. If `work` is still
    /// running then, this returns false and the holder is marked stuck (those
    /// waiting with `acquireUnlessStuck` give up), and `afterStuck` runs once
    /// `work` does return.
    func hand(
        to work: @escaping @Sendable @MainActor () async -> Void,
        waitingAtMost limit: Duration,
        afterStuck: @escaping @Sendable @MainActor () -> Void = {}
    ) async -> Bool {
        precondition(isHeld, "hand(to:) needs the lock held")
        let race = TimedRun()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            race.timer = Task {
                try? await Task.sleep(for: limit)
                // Still running: the lock stays held until it returns.
                guard !Task.isCancelled, !race.workReturned else { return }
                race.timedOut = true
                self.markHolderStuck()
                race.finish(false)
            }
            Task {
                await work()
                race.workReturned = true
                race.timer?.cancel()
                self.release()
                race.finish(true)
                if race.timedOut { afterStuck() }
            }
        }
    }

    private func markHolderStuck() {
        guard isHeld else { return }
        holderIsStuck = true
        let leaving = waiters.filter(\.givesUpIfStuck)
        waiters.removeAll(where: \.givesUpIfStuck)
        for waiter in leaving { waiter.continuation.resume(returning: false) }
    }
}

/// One `hand(to:waitingAtMost:)`: whichever of the work and the timer ends
/// first answers the caller, once.
@MainActor
private final class TimedRun {
    var continuation: CheckedContinuation<Bool, Never>?
    var timer: Task<Void, Never>?
    var workReturned = false
    var timedOut = false

    func finish(_ returnedInTime: Bool) {
        continuation?.resume(returning: returnedInTime)
        continuation = nil
    }
}
