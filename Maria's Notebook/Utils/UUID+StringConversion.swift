import Foundation

/// Extensions for safe UUID string conversion
/// Reduces code duplication and improves readability throughout the codebase
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

extension UUID {
    /// Converts UUID to string (for consistency with String.asUUID)
    var asString: String {
        uuidString
    }
}

