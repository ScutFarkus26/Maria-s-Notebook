import Foundation

// MARK: - What's New Releases

/// One note in a release's What's New card: a symbol and a short line in the classroom voice.
struct WhatsNewNote: Hashable, Sendable {
    let symbol: String
    let text: String
}

/// A release worth telling the guide about. The `id` is what a dismissal remembers,
/// so a new entry here brings the card back and an app update alone does not.
struct WhatsNewRelease: Identifiable, Hashable, Sendable {
    let id: String
    let notes: [WhatsNewNote]
}

enum SettingsWhatsNew {
    /// Newest first. Add a release at the top with a new `id` and two to four short notes.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(id: "2026-09-settings", notes: [
            WhatsNewNote(
                symbol: "waveform",
                text: "Siri can take attendance now. Try “Mark Maya late” or “Undo attendance.”"
            ),
            WhatsNewNote(
                symbol: "magnifyingglass",
                text: "Settings has a new home for everything, and search takes you straight to the setting."
            ),
            WhatsNewNote(
                symbol: "clock.arrow.circlepath",
                text: "Backups can now run every few hours while the app is open."
            ),
            WhatsNewNote(
                symbol: "checklist",
                text: "To-do templates live in Settings › Templates too."
            )
        ])
    ]

    /// The release to show: the newest one, unless the guide already dismissed it.
    static func releaseToShow(
        dismissedID: String,
        releases: [WhatsNewRelease] = releases
    ) -> WhatsNewRelease? {
        guard let newest = releases.first, newest.id != dismissedID else { return nil }
        return newest
    }

    /// The release still waiting to be read, judged from what `defaults` remembers.
    static func pendingRelease(
        in defaults: UserDefaults,
        releases: [WhatsNewRelease] = releases
    ) -> WhatsNewRelease? {
        let dismissedID = defaults.string(forKey: UserDefaultsKeys.whatsNewDismissedRelease) ?? ""
        return releaseToShow(dismissedID: dismissedID, releases: releases)
    }

    /// Remembers that the guide has read `release`, so it stays hidden until a newer one arrives.
    static func dismiss(_ release: WhatsNewRelease, in defaults: UserDefaults) {
        defaults.set(release.id, forKey: UserDefaultsKeys.whatsNewDismissedRelease)
    }
}
