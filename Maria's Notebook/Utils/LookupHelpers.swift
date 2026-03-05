import Foundation

/// Helpers for looking up entities by ID from dictionaries
/// Reduces duplication of UUID string conversion and lookup patterns
extension Dictionary where Key == UUID {
    /// Looks up a value by string ID, converting to UUID first
    /// This is useful for CloudKit-compatible string IDs that need to be looked up in UUID-keyed dictionaries
    /// - Parameter stringID: The ID as a string (from CloudKit-compatible storage)
    /// - Returns: The value if found, nil otherwise
    func lookup(_ stringID: String) -> Value? {
        stringID.asUUID.flatMap { self[$0] }
    }
}
