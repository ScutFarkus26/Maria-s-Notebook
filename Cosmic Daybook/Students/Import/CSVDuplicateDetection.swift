import Foundation

/// Shared duplicate detection utilities for CSV importers.
/// Consolidates common duplicate detection patterns used across CDStudent and CDLesson importers.
enum CSVDuplicateDetection {
    /// Whether a row might already be in the class: its full key (name and
    /// birthday) or its name alone matches a child on file. A name match
    /// counts even when the row has a birthday, since the import then
    /// updates her or, when the birthdays differ, leaves the row out; the
    /// preview used to stay silent about that case.
    /// - Parameters:
    ///   - fullKey: The row's full key
    ///   - nameKey: The row's name-only key
    ///   - existingFullKeys: Set of existing full keys
    ///   - existingNameKeys: Set of existing name-only keys
    /// - Returns: `true` if the item is a potential duplicate
    static func isDuplicate(
        fullKey: String,
        nameKey: String,
        existingFullKeys: Set<String>,
        existingNameKeys: Set<String>
    ) -> Bool {
        existingFullKeys.contains(fullKey) || existingNameKeys.contains(nameKey)
    }

}
