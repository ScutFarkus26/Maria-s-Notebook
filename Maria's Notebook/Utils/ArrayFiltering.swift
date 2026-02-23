import Foundation

/// Helper functions for common array filtering patterns.
/// Reduces duplication in view models and computed properties.
enum ArrayFiltering {
    /// Filters an array based on a set of IDs.
    /// - Parameters:
    ///   - items: Array of items to filter
    ///   - ids: Set of IDs to match
    ///   - idExtractor: Function to extract ID from item
    /// - Returns: Filtered array containing only items with matching IDs
    static func filterByIDs<T>(
        items: [T],
        ids: Set<UUID>,
        idExtractor: (T) -> UUID
    ) -> [T] {
        items.filter { ids.contains(idExtractor($0)) }
    }
    
    /// Filters an array to exclude items with IDs in a set.
    /// - Parameters:
    ///   - items: Array of items to filter
    ///   - excludedIDs: Set of IDs to exclude
    ///   - idExtractor: Function to extract ID from item
    /// - Returns: Filtered array excluding items with matching IDs
    static func excludeByIDs<T>(
        items: [T],
        excludedIDs: Set<UUID>,
        idExtractor: (T) -> UUID
    ) -> [T] {
        items.filter { !excludedIDs.contains(idExtractor($0)) }
    }
    
    /// Filters an array based on a case-insensitive string comparison.
    /// - Parameters:
    ///   - items: Array of items to filter
    ///   - value: String value to match
    ///   - extractor: Function to extract string from item
    /// - Returns: Filtered array containing only matching items
    static func filterByCaseInsensitiveString<T>(
        items: [T],
        value: String,
        extractor: (T) -> String
    ) -> [T] {
        let trimmedValue = value.trimmed()
        return items.filter { extractor($0).caseInsensitiveCompare(trimmedValue) == .orderedSame }
    }
    
    /// Filters an array based on an enum value.
    /// - Parameters:
    ///   - items: Array of items to filter
    ///   - value: Enum value to match
    ///   - extractor: Function to extract enum from item
    /// - Returns: Filtered array containing only matching items
    static func filterByEnum<T, E: Equatable>(
        items: [T],
        value: E,
        extractor: (T) -> E
    ) -> [T] {
        items.filter { extractor($0) == value }
    }
}




