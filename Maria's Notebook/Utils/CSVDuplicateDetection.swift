import Foundation

/// Shared duplicate detection utilities for CSV importers.
/// Consolidates common duplicate detection patterns used across CDStudent and CDLesson importers.
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
    
}
