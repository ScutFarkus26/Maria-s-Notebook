// ScheduledBackupActivity.swift
// The Mac's interval backup, run when the system picks the moment.
//
// Replaces a main-actor `Task.sleep` loop that woke at an exact instant.
// NSBackgroundActivityScheduler chooses the moment inside a window around
// the due time (energy, thermal state, CPU load), calls in at utility QoS,
// and can ask the work to wait (`shouldDefer`). iOS keeps the loop: this API
// is macOS-only, and there the loop only runs while the app is on screen.

#if os(macOS)
import Foundation

/// One non-repeating activity per backup. `arm` registers it, due after the
/// given wait (± a tenth of it); when it fires, `run` performs one backup and
/// returns the wait until the next one, or nil to stop, and the activity
/// re-arms itself with that wait.
@MainActor
final class ScheduledBackupActivity {
    static let identifier = "DanielSDeBerry.MariasNoteBook.scheduledBackup"

    private var scheduler: NSBackgroundActivityScheduler?
    /// Bumped by every `arm` and `invalidate`. A firing that was already on
    /// its way for a replaced activity does nothing, and a run in progress
    /// does not re-arm once the schedule was stopped or restarted meanwhile.
    private var generation = 0

    /// Replaces any armed activity with one due in about `delay` seconds.
    /// `run` performs one backup on the main actor (collection reads the view
    /// context) and returns the wait until the next.
    func arm(after delay: TimeInterval, run: @escaping @MainActor () async -> TimeInterval?) {
        invalidate()
        let armed = generation
        let scheduler = NSBackgroundActivityScheduler(identifier: Self.identifier)
        scheduler.repeats = false
        scheduler.interval = delay
        scheduler.tolerance = ScheduledBackupTiming.tolerance(forDelay: delay)
        scheduler.qualityOfService = .utility
        self.scheduler = scheduler
        // The system calls this block on a utility-QoS serial queue.
        scheduler.schedule { [weak self] completion in
            Task(priority: .utility) { @MainActor [weak self] in
                guard let self else {
                    completion(.finished)
                    return
                }
                await self.fire(armed: armed, run: run, completion: completion)
            }
        }
    }

    /// Stops the armed activity, if any. A run in progress finishes but does
    /// not re-arm.
    func invalidate() {
        generation += 1
        scheduler?.invalidate()
        scheduler = nil
    }

    /// Every path calls `completion` exactly once.
    private func fire(
        armed: Int,
        run: @escaping @MainActor () async -> TimeInterval?,
        completion: @escaping NSBackgroundActivityScheduler.CompletionHandler
    ) async {
        guard armed == generation, let scheduler else {
            // Replaced or stopped after the system had already called in.
            completion(.finished)
            return
        }
        if scheduler.shouldDefer {
            // The system calls this same activity again at a better time.
            completion(.deferred)
            return
        }
        let next = await run()
        completion(.finished)
        guard armed == generation, let next else { return }
        arm(after: next, run: run)
    }
}
#endif
