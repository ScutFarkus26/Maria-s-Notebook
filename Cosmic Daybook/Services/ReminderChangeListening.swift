import Foundation

/// Whether the reminders mirror listens for `.EKEventStoreChanged`.
///
/// Danny decided (2026-09-25) that a configured list EventKit no longer has
/// pauses listening. With 'Girls Class Reminders' gone, every refresh of the
/// calendar daemon re-ran the failing sync: 39 attempts a day on the Mac, each
/// walking the lists, redrawing Today and Settings, and adding two Sync
/// History rows. The pause lasts until the list setting changes (listening
/// resumes and the new choice is tried once) or until a sync started from
/// Today or Settings finds the list after all. Those syncs are not paused, and
/// the error stays on show as before.
nonisolated struct ReminderChangeListening: Equatable, Sendable {
    /// True from a "list not found" until the setting changes or the list turns up.
    private(set) var isPaused = false

    /// Whether to listen, given access and a configured list.
    func shouldListen(hasFullAccess: Bool, isListConfigured: Bool) -> Bool {
        hasFullAccess && isListConfigured && !isPaused
    }

    /// A sync found no list for the setting. True when this starts the pause,
    /// so the caller stops listening once rather than on every failure.
    mutating func pause() -> Bool {
        defer { isPaused = true }
        return !isPaused
    }

    /// The list setting changed, or a sync found the list. True when this
    /// lifts a pause, so the caller listens again (and, after a setting
    /// change, tries the new choice once).
    mutating func resume() -> Bool {
        defer { isPaused = false }
        return isPaused
    }
}
