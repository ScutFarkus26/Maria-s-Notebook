import Foundation

/// Helper functions for common string sorting patterns.
/// Reduces duplication and ensures consistent sorting behavior.
enum StringSorting {
    /// Sorts an array by localized case-insensitive string comparison.
    /// - Parameters:
    ///   - items: Array of items to sort
    ///   - keyPath: Key path to extract the string to compare
    ///   - fallback: Optional fallback comparison function
    /// - Returns: Sorted array
    static func sortByLocalizedCaseInsensitive<T>(
        items: [T],
        keyPath: KeyPath<T, String>,
        fallback: ((T, T) -> Bool)? = nil
    ) -> [T] {
        items.sorted { lhs, rhs in
            let lhsValue = lhs[keyPath: keyPath]
            let rhsValue = rhs[keyPath: keyPath]
            let comparison = lhsValue.localizedCaseInsensitiveCompare(rhsValue)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return fallback?(lhs, rhs) ?? false
        }
    }
    
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
    
    /// Sorts an array by a string extraction function.
    /// - Parameters:
    ///   - items: Array of items to sort
    ///   - extractor: Function to extract the string to compare
    ///   - fallback: Optional fallback comparison function
    /// - Returns: Sorted array
    static func sortByLocalizedCaseInsensitive<T>(
        items: [T],
        extractor: (T) -> String,
        fallback: ((T, T) -> Bool)? = nil
    ) -> [T] {
        items.sorted { lhs, rhs in
            let comparison = extractor(lhs).localizedCaseInsensitiveCompare(extractor(rhs))
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return fallback?(lhs, rhs) ?? false
        }
    }
}
