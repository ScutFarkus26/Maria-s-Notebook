import Foundation

/// Pure functions for filtering, sorting, and computing facets over `[CDStory]`.
/// No external state is mutated; mirrors the `LessonsViewModel` pattern.
@MainActor
struct StoriesViewModel {

    /// Returns the filtered, ordered list of stories for the given filter state.
    func filter(stories: [CDStory], state: StoriesFilterState) -> [CDStory] {
        let query = state.debouncedSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let selectedThemes = state.selectedThemes.map { $0.lowercased() }
        let band = state.selectedGradeBand

        return stories.filter { story in
            // Search: title or any theme.
            if !query.isEmpty {
                let title = story.title.lowercased()
                let themesJoined = story.themesArray.joined(separator: " ").lowercased()
                if !title.contains(query) && !themesJoined.contains(query) {
                    return false
                }
            }
            // Themes: AND-match.
            if !selectedThemes.isEmpty {
                let storyThemes = Set(story.themesArray.map { $0.lowercased() })
                for required in selectedThemes where !storyThemes.contains(required) {
                    return false
                }
            }
            // Grade band intersection.
            if let band, let storyBand = story.gradeBand, !band.intersects(storyBand) {
                return false
            }
            return true
        }
    }

    /// Returns the deduped, alphabetically sorted union of themes across all stories.
    func themesUniverse(from stories: [CDStory]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for story in stories {
            for theme in story.themesArray {
                let trimmed = theme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !trimmed.isEmpty else { continue }
                if seen.insert(trimmed).inserted {
                    ordered.append(trimmed)
                }
            }
        }
        return ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

}
