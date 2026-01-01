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
}

extension UUID {
    /// Converts UUID to string (for consistency with String.asUUID)
    var asString: String {
        uuidString
    }
}

