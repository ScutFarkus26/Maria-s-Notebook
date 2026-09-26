import Foundation

// Kept out of PersistentHistoryProcessor.swift, which posts it: an extension has no
// dependency fingerprint, so a signature edit anywhere in a file that extends
// `Notification.Name` recompiles every file that uses it. See CLAUDE.md, Build-setting
// rules. The Daybook Assistant compiles this file by path, as it does the processor.

extension Notification.Name {
    /// Posted on the main actor after the history processor sees a remote
    /// change to a lesson assignment, lesson, student or work model — the
    /// tables the Upcoming pane and the progress map read. `userInfo` carries
    /// the touched entity names under
    /// `PersistentHistoryProcessor.changedEntityNamesKey`.
    nonisolated static let presentationDataDidChange = Notification.Name("CosmicDaybook.presentationDataDidChange")
}
