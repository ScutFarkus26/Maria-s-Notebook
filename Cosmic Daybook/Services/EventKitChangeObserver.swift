import Foundation
import EventKit

/// One `.EKEventStoreChanged` subscription with trailing-edge coalescing.
///
/// `CalendarSyncService` and `ReminderSyncService` each own one of these.
/// `start` subscribes to the store's change notification. Every change
/// restarts a quiet period, and `handler` runs on the main actor once the
/// store has been quiet for that long. The calendar daemon posts the
/// notification twice, a second or two apart, whenever it refreshes its
/// accounts; before 2026-09-25 each change cancelled the pending task and
/// started one that called the handler at once, and since a cancelled task
/// still runs its body, every post ran a sync. The services keep their own
/// 10-minute throttle inside the handler; this type owns only the
/// subscription and the pending task.
@MainActor
final class EventKitChangeObserver {
    /// How long the store must stay quiet before the handler runs.
    static let defaultQuietPeriod: Duration = .seconds(3)

    private let quietPeriod: Duration
    private var subscription: (any NSObjectProtocol)?
    private var pendingChangeTask: Task<Void, Never>?

    /// True between `start` and `stop`.
    private(set) var isObserving = false

    /// True while a change is waiting out the quiet period.
    var hasPendingChange: Bool { pendingChangeTask != nil }

    init(quietPeriod: Duration = EventKitChangeObserver.defaultQuietPeriod) {
        self.quietPeriod = quietPeriod
    }

    /// Subscribes to the changes `store` posts: the service's `EKEventStore`,
    /// or a stand-in object in tests. A second call while already observing
    /// is a no-op, so callers can re-run `start` whenever their own
    /// preconditions (access, a configured list) come true.
    func start(observing store: AnyObject, handler: @escaping @Sendable @MainActor () async -> Void) {
        guard !isObserving else { return }
        subscription = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            // The observer closure is nonisolated even on the main queue;
            // hop to the main actor before touching the pending task.
            Task { @MainActor [weak self] in
                self?.changeArrived(handler)
            }
        }
        isObserving = true
    }

    /// Cancels any pending handler and removes the subscription.
    func stop() {
        pendingChangeTask?.cancel()
        pendingChangeTask = nil
        if let subscription {
            NotificationCenter.default.removeObserver(subscription)
            self.subscription = nil
        }
        isObserving = false
    }

    /// Restarts the quiet period; the handler runs if it ends undisturbed.
    private func changeArrived(_ handler: @escaping @Sendable @MainActor () async -> Void) {
        // A change delivered just before `stop` must not start a sync after it.
        guard isObserving else { return }
        pendingChangeTask?.cancel()
        pendingChangeTask = Task { [weak self, quietPeriod] in
            do {
                try await Task.sleep(for: quietPeriod)
            } catch {
                return // a newer change, or `stop`, superseded this one
            }
            guard !Task.isCancelled, let self else { return }
            self.pendingChangeTask = nil
            await handler()
        }
    }
}
