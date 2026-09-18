import Foundation

/// Helper functions for common string sorting patterns.
/// Reduces duplication and ensures consistent sorting behavior.
enum StringSorting {
    /// Sorts an array by multiple localized case-insensitive string comparisons.
    /// - Parameters:
    ///   - items: Array of items to sort
    ///   - keyPaths: Array of key paths to compare in order
    ///   - fallback: Optional fallback comparison function
    /// - Returns: Sorted array
    static func sortByMultipleLocalizedCaseInsensitive<T>(
        items: [T],
        keyPaths: [KeyPath<T, String>],
        fallback: ((T, T) -> Bool)? = nil
    ) -> [T] {
        items.sorted { lhs, rhs in
            for keyPath in keyPaths {
                let lhsValue = lhs[keyPath: keyPath]
                let rhsValue = rhs[keyPath: keyPath]
                let comparison = lhsValue.localizedCaseInsensitiveCompare(rhsValue)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            }
            return fallback?(lhs, rhs) ?? false
        }
    }
}
