import Foundation
import Testing
@testable import CosmicDaybook

/// Pins the Settings sidebar and its search: every card names a real category,
/// a selection saved before the 2026-09-29 regroup still opens, and search finds
/// the settings a guide looks for (and nothing that's gone).
@Suite("Settings catalog")
struct SettingsCatalogTests {

    @Test("Every category but Overview has at least one card")
    func everyCategoryHasCards() {
        for category in SettingsCategory.allCases where category != .overview {
            #expect(!category.groups.isEmpty, "\(category) has no cards")
        }
        #expect(SettingsCategory.overview.groups.isEmpty)
    }

    @Test("Card titles and scroll anchors are unique")
    func titlesAndAnchorsAreUnique() {
        let groups = SettingsCopy.Group.allCases
        #expect(Set(groups.map(\.title)).count == groups.count)
        #expect(Set(groups.map(\.anchorID)).count == groups.count)
        #expect(Set(SettingsCategory.allCases.map(\.displayName)).count == SettingsCategory.allCases.count)
    }

    @Test("A selection saved by an older build opens the category that took it over")
    func legacySelectionsMap() {
        #expect(SettingsCategory(storedValue: "general") == .schoolYear)
        #expect(SettingsCategory(storedValue: "dataSync") == .syncBackup)
        #expect(SettingsCategory(storedValue: "backup") == .syncBackup)
        #expect(SettingsCategory(storedValue: "communication") == .messages)
        #expect(SettingsCategory(storedValue: "aiFeatures") == .intelligence)
        #expect(SettingsCategory(storedValue: "database") == .troubleshooting)
        #expect(SettingsCategory(storedValue: "advanced") == .troubleshooting)
        #expect(SettingsCategory(storedValue: "classroom") == .classroom)
        #expect(SettingsCategory(storedValue: "templates") == .templates)
        #expect(SettingsCategory(storedValue: "") == nil)
        #expect(SettingsCategory(storedValue: "somethingElse") == nil)
    }

    @Test(
        "Search finds each setting in the category that holds it",
        arguments: [
            ("school calendar", SettingsCategory.schoolYear),
            ("days off", .schoolYear),
            ("rollover", .schoolYear),
            ("assistant", .classroom),
            ("age indicators", .lookAndFeel),
            ("quick capture", .lookAndFeel),
            ("parent reports", .messages),
            ("order requests", .messages),
            ("to-do templates", .templates),
            ("apple calendar", .connections),
            ("reminders", .connections),
            ("private cloud", .intelligence),
            ("siri", .intelligence),
            ("back up every", .syncBackup),
            ("merge", .syncBackup),
            ("move settings", .syncBackup),
            ("sync history", .troubleshooting),
            ("reset local cache", .troubleshooting),
            ("notebook at a glance", .troubleshooting)
        ]
    )
    func searchFindsSetting(query: String, category: SettingsCategory) {
        #expect(category.matches(query), "\"\(query)\" should find \(category)")
    }

    @Test("Search ignores case and accents")
    func searchIsForgiving() {
        #expect(SettingsCategory.syncBackup.matches("ICLOUD"))
        #expect(SettingsCategory.troubleshooting.matches("Ré-download"))
    }

    @Test("Search doesn't find settings that were removed")
    func searchSkipsRemovedSettings() {
        for query in ["temperature", "API key", "encrypted", "retention", "dev snapshots"] {
            let hits = SettingsCategory.allCases.filter { $0.matches(query) }
            #expect(hits.isEmpty, "\"\(query)\" still finds \(hits)")
        }
    }

    @Test("Claude Desktop is listed only where it exists")
    func claudeDesktopIsMacOnly() {
        #if os(macOS)
        #expect(SettingsCategory.connections.groups.contains(.claudeDesktop))
        #else
        #expect(!SettingsCategory.connections.groups.contains(.claudeDesktop))
        #expect(!SettingsCategory.connections.matches("claude"))
        #endif
    }
}
