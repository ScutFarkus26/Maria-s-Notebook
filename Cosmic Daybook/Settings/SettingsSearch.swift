import Foundation

// MARK: - Settings Search

/// Where a search takes the guide inside a category: the cards that match, in
/// the order the pane shows them.
enum SettingsSearch {
    /// True once the query holds more than spaces.
    static func isSearching(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The category's cards whose title or keywords match; empty when not searching.
    static func matchingGroups(in category: SettingsCategory, query: String) -> [SettingsCopy.Group] {
        guard isSearching(query) else { return [] }
        return category.groups.filter { $0.matches(query) }
    }

    /// The card a search scrolls to in the open category.
    static func firstMatchingGroup(in category: SettingsCategory, query: String) -> SettingsCopy.Group? {
        matchingGroups(in: category, query: query).first
    }
}

/// A pane pushed on iPhone, opened at one card when it came from a search result.
struct SettingsPaneRoute: Hashable {
    let category: SettingsCategory
    var focus: SettingsCopy.Group?
}
