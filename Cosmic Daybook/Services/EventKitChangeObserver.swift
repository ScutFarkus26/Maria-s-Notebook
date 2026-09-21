import Foundation
import EventKit

/// One `.EKEventStoreChanged` subscription with coalesced delivery.
///
/// `CalendarSyncService` and `ReminderSyncService` each own one of these.
/// `start` subscribes to the store's change notification and hands every
/// change to `handler` on the main actor; a change that arrives while an
/// earlier handler is still pending cancels that task and starts a fresh
/// one, so a burst of iCloud updates yields a single sync. The services keep
/// their own 30-second "synced recently" debounce inside the handler — this
/// type owns only the subscription and the pending task.
@MainActor
final class EventKitChangeObserver {
    private var subscription: (any NSObjectProtocol)?
    private var pendingChangeTask: Task<Void, Never>?

    /// True between `start` and `stop`.
    private(set) var isObserving = false

    /// Subscribes to `eventStore`'s changes. A second call while already
    /// observing is a no-op, so callers can re-run `start` whenever their
    /// own preconditions (access, a configured list) come true.
    func start(eventStore: EKEventStore, handler: @escaping @Sendable @MainActor () async -> Void) {
        guard !isObserving else { return }
        subscription = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            // The observer closure is nonisolated even on the main queue;
            // hop to the main actor before touching the pending task.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingChangeTask?.cancel()
                self.pendingChangeTask = Task { @MainActor in
                    await handler()
                }
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
}
