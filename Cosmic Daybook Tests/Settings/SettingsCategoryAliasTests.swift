import Foundation
import Testing
@testable import CosmicDaybook

/// Pins the six Settings categories' saved raw values and the aliases for
/// the four retired 2026-11-03, so a selection an older build saved still
/// opens the category that took it over.
@Suite("Settings category aliases")
struct SettingsCategoryAliasTests {

    @Test(
        "A retired category's saved selection opens the one that absorbed it",
        arguments: [
            ("overview", SettingsCategory.schoolYear),
            ("messages", .lookAndFeel),
            ("connections", .intelligence),
            ("troubleshooting", .syncBackup)
        ]
    )
    func retiredCategoriesLand(stored: String, category: SettingsCategory) {
        #expect(SettingsCategory(rawValue: stored) == nil, "\(stored) is a case again")
        #expect(SettingsCategory(storedValue: stored) == category)
    }

    @Test("The six raw values are the saved ones, never renamed")
    func rawValuesArePinned() {
        #expect(SettingsCategory.allCases.map(\.rawValue)
            == ["schoolYear", "classroom", "lookAndFeel", "templates", "syncBackup", "intelligence"])
        for category in SettingsCategory.allCases {
            #expect(SettingsCategory(storedValue: category.rawValue) == category)
        }
    }

    @Test("Every alias lands on a live category, and none shadows a case")
    func aliasesAreSound() {
        for (stored, category) in SettingsCategory.aliases {
            #expect(SettingsCategory(rawValue: stored) == nil, "\(stored) shadows a case")
            #expect(SettingsCategory.allCases.contains(category))
        }
    }

    @Test("Nothing saved, or something unknown, opens on School year")
    func landing() {
        #expect(SettingsCategory(storedValue: "") == nil)
        #expect(SettingsCategory(storedValue: "somethingElse") == nil)
        #expect(SettingsCategory.landing == .schoolYear)
    }

    @Test("A card moved with its category")
    func cardsMoved() {
        #expect(SettingsCopy.Group.attendanceEmail.category == .lookAndFeel)
        #expect(SettingsCopy.Group.appleCalendar.category == .intelligence)
        #expect(SettingsCopy.Group.tide.category == .intelligence)
        #expect(SettingsCopy.Group.syncHistory.category == .syncBackup)
        #expect(SettingsCopy.Group.maintenance.category == .syncBackup)
    }
}
