// AlbumSaveDebouncer.swift
// Holds a save for a moment after each change, one key at a time, so a change
// under one key never cancels another key's save. The album reader keeps one
// for its Pencil ink (by page) and one for its reading position (by album).

/// Debounces saves per key. A key's save runs `delay` after that key's last
/// change; a newer change under the same key replaces the save still waiting,
/// and a change under any other key leaves it alone.
///
/// The reader's ink used to share one save task among all pages, so drawing
/// on page B within the window cancelled page A's save and page A's ink never
/// reached the store; it is keyed by page now. The reading position waits 1.5 s
/// for page turns to settle, as one key. `flush()` saves everything still
/// waiting at once: the reader flushes both when its scene goes to the
/// background, so an iOS kill there loses neither, and flushes ink when it
/// closes. `cancelAll()` drops what is waiting, unsaved: on closing, the reader
/// writes the page it is on itself, as it always has.
@MainActor
final class AlbumSaveDebouncer<Key: Hashable & Comparable & Sendable, C: Clock> where C.Duration == Duration {
    let delay: Duration
    private let clock: C
    private var pending: [Key: PendingSave] = [:]

    private struct PendingSave {
        let task: Task<Void, Never>
        let save: () -> Void
    }

    init(delay: Duration, clock: C) {
        self.delay = delay
        self.clock = clock
    }

    /// Keys whose save is still waiting, in order.
    var waitingKeys: [Key] { pending.keys.sorted() }

    /// Runs `save` once `delay` passes with no newer change under `key`,
    /// replacing the key's save if one is still waiting.
    func schedule(_ key: Key, save: @escaping () -> Void) {
        pending[key]?.task.cancel()
        let deadline = clock.now.advanced(by: delay)
        // The task keeps the debouncer alive until it has saved, as the old
        // single task kept the reader's context alive.
        let task = Task { [clock] in
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                return // Replaced by a newer change, flushed or cancelled.
            }
            self.saveIfCurrent(key)
        }
        pending[key] = PendingSave(task: task, save: save)
    }

    /// Saves everything still waiting, now, in key order.
    func flush() {
        let waiting = pending.sorted { $0.key < $1.key }
        pending.removeAll()
        for (_, entry) in waiting {
            entry.task.cancel()
            entry.save()
        }
    }

    /// Drops everything still waiting without saving it.
    func cancelAll() {
        for entry in pending.values { entry.task.cancel() }
        pending.removeAll()
    }

    private func saveIfCurrent(_ key: Key) {
        // Replacing, flushing or cancelling a save cancels its task; one that
        // woke before the cancel reached it holds a change that is no longer
        // the key's latest.
        guard !Task.isCancelled, let entry = pending.removeValue(forKey: key) else { return }
        entry.save()
    }
}
