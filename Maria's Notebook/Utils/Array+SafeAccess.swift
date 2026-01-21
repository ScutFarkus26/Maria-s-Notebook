import Foundation

/// Safe array access extensions to prevent index-out-of-bounds crashes
extension Array {
    /// Safely access array element by index, returning nil if index is out of bounds
    /// - Parameter index: The index to access
    /// - Returns: The element at the index, or nil if index is invalid
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

extension Collection {
    /// Safely access collection element by index, returning nil if index is out of bounds
    /// - Parameter index: The index to access
    /// - Returns: The element at the index, or nil if index is invalid
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

/// Safe first access that returns nil instead of crashing
extension Collection {
    /// Returns the first element safely (always safe, but included for consistency)
    var safeFirst: Element? {
        return first
    }
}

// MARK: - Deduplication

extension Array where Element: Identifiable {
    /// Returns an array with duplicate elements removed, keeping the first occurrence of each ID.
    /// CloudKit sync can create duplicate records with the same ID during merge conflicts.
    /// Use this to prevent SwiftUI crashes like "Duplicate values for key" in ForEach loops.
    var uniqueByID: [Element] {
        var seenIDs = Set<Element.ID>()
        return filter { element in
            if seenIDs.contains(element.id) {
                return false
            }
            seenIDs.insert(element.id)
            return true
        }
    }
}

