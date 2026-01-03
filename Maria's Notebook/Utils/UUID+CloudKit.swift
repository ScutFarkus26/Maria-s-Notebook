import Foundation

/// Extensions for UUID to String conversion for CloudKit compatibility.
/// CloudKit requires UUID foreign keys to be stored as strings.
extension UUID {
    /// Returns the UUID as a string for CloudKit storage.
    /// This is the canonical way to convert UUIDs to strings for CloudKit compatibility.
    var cloudKitString: String {
        uuidString
    }
}

/// Helper functions for CloudKit UUID conversions.
enum CloudKitUUID {
    /// Converts a UUID to a string for CloudKit storage.
    /// - Parameter uuid: The UUID to convert
    /// - Returns: The UUID as a string
    static func string(from uuid: UUID) -> String {
        uuid.uuidString
    }
    
    /// Converts a string to a UUID, returning nil if invalid.
    /// - Parameter string: The string to convert
    /// - Returns: The UUID if valid, nil otherwise
    static func uuid(from string: String) -> UUID? {
        UUID(uuidString: string)
    }
    
    /// Converts an array of UUIDs to an array of strings for CloudKit storage.
    /// - Parameter uuids: The UUIDs to convert
    /// - Returns: Array of UUID strings
    static func strings(from uuids: [UUID]) -> [String] {
        uuids.map { $0.uuidString }
    }
    
    /// Converts an array of strings to an array of UUIDs, filtering out invalid ones.
    /// - Parameter strings: The strings to convert
    /// - Returns: Array of valid UUIDs
    static func uuids(from strings: [String]) -> [UUID] {
        strings.compactMap { UUID(uuidString: $0) }
    }
}



