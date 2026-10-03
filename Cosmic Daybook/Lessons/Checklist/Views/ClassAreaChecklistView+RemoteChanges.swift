// ClassAreaChecklistView+RemoteChanges.swift
// Since a click refreshes only the rows it can reach, edits synced in from another
// device would otherwise wait for the next full rebuild (area switch, return to the
// screen). The history processor's import signal brings them in instead.

import Combine
import Foundation

extension ClassAreaChecklistView {
    /// Imported entities that can move a cell: its lesson, its child, the plans and
    /// presentations, and the work.
    nonisolated static let remoteRefreshEntityNames: Set<String> = [
        "LessonAssignment", "Lesson", "Student", "WorkModel"
    ]

    /// Imports from another device that touched the grid's records, settled for a second so a
    /// sync burst rebuilds once. `.presentationDataDidChange` comes from the history processor,
    /// which leaves out this app's own saves, so a click here never triggers a full rebuild.
    static func remoteRecordChanges() -> some Publisher<Void, Never> {
        NotificationCenter.default.publisher(for: .presentationDataDidChange)
            // @Sendable: filter closures run on the posting thread (see onPresentationDataChange).
            .filter { @Sendable note in
                let key = PersistentHistoryProcessor.changedEntityNamesKey
                guard let changed = note.userInfo?[key] as? Set<String> else { return true }
                return !changed.isDisjoint(with: remoteRefreshEntityNames)
            }
            .map { @Sendable _ in () }
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
    }
}
