// IdleCountdown.swift
// Runs an action once a quiet spell has passed since the last touch. The
// album search uses it to let go of its language model a few minutes after
// the last search, instead of holding it until a memory warning.

import Synchronization

/// Runs `action` once `interval` has passed since the last `touch()`.
///
/// Every touch pushes the deadline back. One countdown task at a time sleeps
/// until the deadline; waking to find it moved, it sleeps again until the new
/// one, so a burst of touches costs no task per touch. `touch()` is cheap,
/// synchronous and safe from any thread. The action runs off the main actor,
/// under the countdown's lock, so no touch can slip in between deciding to
/// fire and firing.
nonisolated final class IdleCountdown<C: Clock>: Sendable where C.Duration == Duration {
    let interval: Duration
    private let clock: C
    private let tolerance: Duration?
    private let action: @Sendable () -> Void
    private let state = Mutex(State())

    private struct State {
        var deadline: C.Instant?
        var isCounting = false
    }

    init(interval: Duration, tolerance: Duration? = nil, clock: C,
         action: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.tolerance = tolerance
        self.clock = clock
        self.action = action
    }

    /// When the action runs unless something touches the countdown first;
    /// nil when nothing is counting down.
    var deadline: C.Instant? { state.withLock { $0.deadline } }

    /// Starts the countdown, or pushes it back to a full interval from now.
    func touch() {
        let deadline = clock.now.advanced(by: interval)
        let startsCounting = state.withLock { state in
            state.deadline = deadline
            guard !state.isCounting else { return false }
            state.isCounting = true
            return true
        }
        guard startsCounting else { return }
        Task(priority: .utility) { await self.countDown() }
    }

    @concurrent private func countDown() async {
        while true {
            let next = state.withLock { state -> C.Instant? in
                if state.deadline == nil { state.isCounting = false }
                return state.deadline
            }
            guard let next else { return }
            do {
                try await clock.sleep(until: next, tolerance: tolerance)
            } catch {
                // Only cancellation throws, and nothing cancels this task. If
                // it ever does, the next touch starts a fresh countdown.
                state.withLock { $0.isCounting = false }
                return
            }
            let fired = state.withLock { state -> Bool in
                guard let deadline = state.deadline, deadline <= clock.now else { return false }
                state.deadline = nil
                state.isCounting = false
                action()
                return true
            }
            if fired { return }
        }
    }
}
