import Foundation

// Extensions for safe UUID ↔ String conversion.
// Consolidates all UUID/String helpers into a single file.

// MARK: - String → UUID

extension String {
    /// Safely converts string to UUID, returns nil if invalid
    var asUUID: UUID? {
        UUID(uuidString: self)
    }
}

// MARK: - Collection UUID Strings

extension Collection where Element: Identifiable, Element.ID == UUID {
    /// Returns an array of UUID strings for all elements in the collection
    nonisolated var uuidStrings: [String] {
        map { $0.id.uuidString }
    }
}
