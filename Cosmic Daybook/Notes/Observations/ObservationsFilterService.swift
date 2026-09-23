import Foundation

// MARK: - Observations Filter Service

/// Filters observation items based on category, scope, and search text.
enum ObservationsFilterService {

    // MARK: - Tag Menu

    /// Every tag used by `items`, sorted by display name — the tag menu's rows.
    static func usedTags(in items: [UnifiedObservationItem]) -> [String] {
        Set(items.flatMap { $0.tags }).sorted { TagHelper.tagName($0) < TagHelper.tagName($1) }
    }

    // MARK: - Scope Filter

    enum ScopeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case studentSpecific = "Student-specific"
        case allStudents = "All students"

        var id: String { rawValue }
    }

    // MARK: - Apply Filters

    /// Filters observation items based on tags, scope, and search text.
    ///
    /// - Parameters:
    ///   - items: Items to filter
    ///   - filterTags: Tags to filter by (empty means no filter)
    ///   - scope: Scope filter
    ///   - searchText: Search text filter
    /// - Returns: Filtered items
    static func filter(
        items: [UnifiedObservationItem],
        filterTags: Set<String>,
        scope: ScopeFilter,
        searchText: String
    ) -> [UnifiedObservationItem] {
        var result = items

        // Tag filter
        if !filterTags.isEmpty {
            result = result.filter { item in
                !filterTags.isDisjoint(with: item.tags)
            }
        }

        // Scope filter
        switch scope {
        case .all:
            break
        case .studentSpecific:
            result = result.filter { !$0.studentIDs.isEmpty }
        case .allStudents:
            result = result.filter { $0.studentIDs.isEmpty }
        }

        // Search text filter
        let query = searchText.trimmed()
        if !query.isEmpty {
            result = result.filter { $0.body.localizedCaseInsensitiveContains(query) }
        }

        return result
    }
}
