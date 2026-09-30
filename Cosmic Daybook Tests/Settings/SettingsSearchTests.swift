import Foundation
import Testing
@testable import CosmicDaybook

/// Pins where a search lands inside a category: the first card that matches,
/// in the order the pane shows its cards.
@Suite("Settings search")
struct SettingsSearchTests {

    @Test("No query, or only spaces, finds no card to jump to")
    func emptyQuery() {
        for category in SettingsCategory.allCases {
            #expect(SettingsSearch.firstMatchingGroup(in: category, query: "") == nil)
            #expect(SettingsSearch.firstMatchingGroup(in: category, query: "   ") == nil)
            #expect(SettingsSearch.matchingGroups(in: category, query: " ").isEmpty)
        }
        #expect(!SettingsSearch.isSearching(" \n"))
        #expect(SettingsSearch.isSearching(" backup "))
    }

    @Test("A control's label finds its card")
    func keywordFindsCard() {
        #expect(SettingsSearch.firstMatchingGroup(in: .syncBackup, query: "Include note photos") == .backups)
        #expect(SettingsSearch.firstMatchingGroup(in: .troubleshooting, query: "reset local cache") == .maintenance)
        #expect(SettingsSearch.firstMatchingGroup(in: .lookAndFeel, query: "pie menu") == .quickCapture)
        // School year's cards are being split up; ask by words, not by card.
        for query in ["rollover", "days off"] {
            let group = SettingsSearch.firstMatchingGroup(in: .schoolYear, query: query)
            #expect(group?.category == .schoolYear, "\(query) finds no School year card")
        }
    }

    @Test("Matching ignores case and accents")
    func caseAndDiacritics() {
        #expect(SettingsSearch.firstMatchingGroup(in: .messages, query: "PARENT") == .parentReports)
        #expect(SettingsSearch.firstMatchingGroup(in: .intelligence, query: "sirì") == .siri)
    }

    @Test("Several matches land on the first card the pane shows")
    func firstInPaneOrder() {
        // "Templates" is a keyword of all three template cards.
        #expect(SettingsSearch.matchingGroups(in: .templates, query: "templates")
            == [.noteTemplates, .meetingTemplates, .todoTemplates])
        #expect(SettingsSearch.firstMatchingGroup(in: .templates, query: "templates") == .noteTemplates)
        // "Sync" is on the iCloud card and the Sync history card, in different categories.
        #expect(SettingsSearch.firstMatchingGroup(in: .syncBackup, query: "sync") == .iCloud)
        #expect(SettingsSearch.firstMatchingGroup(in: .troubleshooting, query: "sync") == .syncHistory)
    }

    @Test("A card in another category is never the jump target")
    func staysInCategory() {
        #expect(SettingsSearch.firstMatchingGroup(in: .overview, query: "backup") == nil)
        #expect(SettingsSearch.firstMatchingGroup(in: .messages, query: "Include note photos") == nil)
        for category in SettingsCategory.allCases {
            for group in SettingsSearch.matchingGroups(in: category, query: "a") {
                #expect(group.category == category)
            }
        }
    }
}
