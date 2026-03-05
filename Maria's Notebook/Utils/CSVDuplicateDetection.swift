import Foundation

/// Shared duplicate detection utilities for CSV importers.
/// Consolidates common duplicate detection patterns used across Student and Lesson importers.
enum CSVDuplicateDetection {
    /// Detects if a key exists in the provided sets.
    /// - Parameters:
    ///   - key: The full key to check
    ///   - nameKey: The name-only key to check (used as fallback)
    ///   - existingFullKeys: Set of existing full keys
    ///   - existingNameKeys: Set of existing name-only keys
    ///   - hasFullKey: Whether the item has a full key (e.g., has birthday)
    /// - Returns: `true` if the item is a potential duplicate
    static func isDuplicate(
        fullKey: String,
        nameKey: String,
        existingFullKeys: Set<String>,
        existingNameKeys: Set<String>,
        hasFullKey: Bool
    ) -> Bool {
        if existingFullKeys.contains(fullKey) {
            return true
        } else if !hasFullKey && existingNameKeys.contains(nameKey) {
            return true
        }
        return false
    }
    
    /// Builds duplicate key sets from an array of items with IDs.
    /// - Parameters:
    ///   - items: Array of items to extract keys from
    ///   - fullKeyExtractor: Function to extract full key from item
    ///   - nameKeyExtractor: Function to extract name-only key from item
    /// - Returns: Tuple of (fullKeys, nameKeys) sets
    static func buildKeySets<T>(
        from items: [T],
        fullKeyExtractor: (T) -> String,
        nameKeyExtractor: (T) -> String
    ) -> (fullKeys: Set<String>, nameKeys: Set<String>) {
        let fullKeys = Set(items.map(fullKeyExtractor))
        let nameKeys = Set(items.map(nameKeyExtractor))
        return (fullKeys, nameKeys)
    }
}
