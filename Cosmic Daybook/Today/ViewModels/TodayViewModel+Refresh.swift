// TodayViewModel+Refresh.swift
// When Today reloads: the debounce, and the edits from other windows and
// other devices that ask for a reload.
//
// Today's own actions reload at once (`reload()`). Until 2026-10-02 nothing
// reloaded it when a work, a presentation or a check-in changed in another
// window, so the Mac's Today went stale beside an open work window.

import Combine
import CoreData
import Foundation
import OSLog

extension TodayViewModel {

    /// The entities whose edits elsewhere should reload Today. Not
    /// "TodoItem": nothing `reload()` builds reads a todo (the Todos section
    /// keeps its own fetch, which follows every save), and a reload on each
    /// todo tick is what the ready queue's gate was built to avoid. Add it
    /// when the model starts reading todos (the work rows' linked todos).
    nonisolated static let reloadInputEntities: Set<String> = [
        "WorkModel", "LessonAssignment", "WorkCheckIn"
    ]

    /// `reload()` as an Instruments interval ("Today" category).
    nonisolated static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cosmicdaybook",
        category: "Today"
    )

    /// Saves that touch one of `reloadInputEntities`, on any context — another
    /// window's, the MCP bridge's, the CloudKit import's — delivered on the
    /// main run loop. Not debounced here: the view re-creates this publisher
    /// on every update, which would drop a pending debounced value, so the
    /// debounce lives in `scheduleReloadIfInputsChanged`, on the model.
    ///
    /// No `.presentationDataDidChange`: the history processor posts it for
    /// local saves too, a beat after Today's own reload, and the import it
    /// reports has already arrived here as the import context's save.
    nonisolated static func inputChanges() -> some Publisher<Void, Never> {
        let entities = reloadInputEntities
        return NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            // @Sendable: runs on the saving context's queue.
            .filter { @Sendable note in ManagedObjectChangeScope.saveTouches(entities, in: note.userInfo) }
            .map { @Sendable _ in () }
            .receive(on: RunLoop.main)
    }

    /// A save touched one of `reloadInputEntities`. Debounced like
    /// `scheduleReload()`, then reloads only if the change landed after the
    /// last reload (`reloadInputs`): Today's own edits reload at once, and
    /// their save, arriving here after that reload, asks for nothing more.
    func scheduleReloadIfInputsChanged() {
        debounceReload()
    }

    func debounceReload() {
        // Cancel any pending reload
        reloadTask?.cancel()

        // Schedule a debounced reload (400ms delay balances responsiveness with energy efficiency)
        reloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(400)) // 400ms debounce
                guard !Task.isCancelled else { return }
                if reloadIsRequired || reloadInputs.consume(pendingIn: context) {
                    reload()
                }
            } catch {
                // Task was cancelled, ignore
            }
        }
    }
}
