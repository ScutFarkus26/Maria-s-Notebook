// AlbumInkSaveDebouncer.swift
// Holds the album reader's Pencil ink for a moment after each change and then
// saves it, one page at a time, so a change on one page never cancels another
// page's save.

#if os(iOS)
/// Debounces the reader's ink saves per page. A page's save runs `delay` after
/// that page's last change; a newer drawing of the same page replaces the save
/// still waiting for it, and a change on any other page leaves it alone.
///
/// The reader used to keep one save task for every page, so drawing on page B
/// within the window cancelled page A's save and page A's ink never reached
/// the store. `flush()` saves everything still waiting at once: the reader
/// calls it when it closes and when its scene goes to the background.
@MainActor
final class AlbumInkSaveDebouncer<C: Clock> where C.Duration == Duration {
    let delay: Duration
    private let clock: C
    private var pending: [Int: PendingSave] = [:]

    private struct PendingSave {
        let task: Task<Void, Never>
        let save: () -> Void
    }

    init(delay: Duration, clock: C) {
        self.delay = delay
        self.clock = clock
    }

    /// Pages whose save is still waiting, lowest first.
    var pendingPages: [Int] { pending.keys.sorted() }

    /// Runs `save` once `delay` passes with no newer change to the page,
    /// replacing the page's save if one is still waiting.
    func schedule(pageIndex: Int, save: @escaping () -> Void) {
        pending[pageIndex]?.task.cancel()
        let deadline = clock.now.advanced(by: delay)
        // The task keeps the debouncer alive until it has saved, as the old
        // single task kept the reader's context alive.
        let task = Task { [clock] in
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                return // Replaced by a newer drawing, or flushed.
            }
            self.saveIfCurrent(pageIndex)
        }
        pending[pageIndex] = PendingSave(task: task, save: save)
    }

    /// Saves every page still waiting, now, lowest page first.
    func flush() {
        let waiting = pending.sorted { $0.key < $1.key }
        pending.removeAll()
        for (_, entry) in waiting {
            entry.task.cancel()
            entry.save()
        }
    }

    private func saveIfCurrent(_ pageIndex: Int) {
        // Replacing or flushing a save cancels its task; one that woke before
        // the cancel reached it holds a drawing that is no longer the page's.
        guard !Task.isCancelled, let entry = pending.removeValue(forKey: pageIndex) else { return }
        entry.save()
    }
}
#endif
