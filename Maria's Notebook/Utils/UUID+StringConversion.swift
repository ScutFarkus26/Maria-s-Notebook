import Foundation

// Extensions for safe UUID ↔ String conversion.
// Consolidates all UUID/String helpers into a single file.

// MARK: - String → UUID

extension String {
    /// Safely converts string to UUID, returns nil if invalid
    var asUUID: UUID? {
        UUID(uuidString: self)
    }

    /// Converts string to UUID with fallback to new UUID
    /// Use when a valid UUID is required but the string might be invalid
    var asUUIDOrNew: UUID {
        UUID(uuidString: self) ?? UUID()
    }

    /// Converts string to UUID with custom fallback value
    /// Use when a specific default UUID is needed instead of generating a new one
    /// - Parameter defaultValue: The UUID to return if conversion fails
    /// - Returns: The converted UUID or the default value
    func asUUID(or defaultValue: UUID) -> UUID {
        UUID(uuidString: self) ?? defaultValue
    }
}

// MARK: - Collection UUID Strings

extension Collection where Element: Identifiable, Element.ID == UUID {
    /// Returns an array of UUID strings for all elements in the collection
    nonisolated var uuidStrings: [String] {
        map { $0.id.uuidString }
    }
}

extension Sequence where Element: Identifiable, Element.ID == UUID {
    /// Returns an array of UUID strings for all elements in the sequence
    nonisolated var uuidStrings: [String] {
        map { $0.id.uuidString }
    }
}
