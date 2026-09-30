import Foundation
import Testing
@testable import CosmicDaybook

/// Pins the What's New rule: the newest release shows until it is dismissed, a dismissal
/// is remembered by release id (not app version), and a newer release brings the card back.
@Suite("What's New shows once per release")
@MainActor
struct SettingsWhatsNewTests {

    private let suiteName = "SettingsWhatsNewTests-\(UUID().uuidString)"

    private func isolatedDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    private func release(_ id: String) -> WhatsNewRelease {
        WhatsNewRelease(id: id, notes: [
            WhatsNewNote(symbol: "star", text: "One"),
            WhatsNewNote(symbol: "star", text: "Two")
        ])
    }

    @Test("A guide who has dismissed nothing sees the newest release")
    func freshDefaultsShowNewest() throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let releases = [release("b"), release("a")]

        #expect(SettingsWhatsNew.pendingRelease(in: defaults, releases: releases)?.id == "b")
    }

    @Test("Dismissing the newest release hides it")
    func dismissHides() throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let releases = [release("b"), release("a")]

        SettingsWhatsNew.dismiss(releases[0], in: defaults)

        #expect(SettingsWhatsNew.pendingRelease(in: defaults, releases: releases) == nil)
        #expect(defaults.string(forKey: UserDefaultsKeys.whatsNewDismissedRelease) == "b")
    }

    @Test("A newer release comes back after the last one was dismissed")
    func newerReleaseReturns() throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SettingsWhatsNew.dismiss(release("a"), in: defaults)
        let later = [release("b"), release("a")]

        #expect(SettingsWhatsNew.pendingRelease(in: defaults, releases: later)?.id == "b")
    }

    @Test("Dismissing an older release does not hide the newest")
    func olderDismissalKeepsNewest() {
        let releases = [release("b"), release("a")]
        #expect(SettingsWhatsNew.releaseToShow(dismissedID: "a", releases: releases)?.id == "b")
        #expect(SettingsWhatsNew.releaseToShow(dismissedID: "b", releases: releases) == nil)
    }

    @Test("No releases means no card")
    func emptyListShowsNothing() {
        #expect(SettingsWhatsNew.releaseToShow(dismissedID: "", releases: []) == nil)
    }

    @Test("Each shipped release has a unique id and two to four short notes")
    func shippedReleasesAreWellFormed() {
        let ids = SettingsWhatsNew.releases.map(\.id)
        #expect(!ids.isEmpty)
        #expect(Set(ids).count == ids.count)
        for release in SettingsWhatsNew.releases {
            #expect((2...4).contains(release.notes.count), "\(release.id) has \(release.notes.count) notes")
            for note in release.notes {
                #expect(!note.text.isEmpty)
                #expect(!note.text.contains("(s)"), "Use a real plural: \(note.text)")
            }
        }
    }
}
