import Foundation

/// Helper functions for common string fallback patterns.
/// Reduces duplication in empty string handling.
enum StringFallbacks {
    /// Returns the value if not empty, otherwise returns the fallback.
    /// - Parameters:
    ///   - value: The string value to check
    ///   - fallback: The fallback value if the string is empty
    /// - Returns: The value if not empty, otherwise the fallback
    static func valueOrFallback(_ value: String, fallback: String) -> String {
        value.isEmpty ? fallback : value
    }
    
    /// Returns the value if not empty, otherwise returns nil.
    /// - Parameter value: The string value to check
    /// - Returns: The value if not empty, otherwise nil
    static func valueOrNil(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
    
    /// Returns the trimmed value if not empty, otherwise returns the fallback.
    /// - Parameters:
    ///   - value: The string value to check
    ///   - fallback: The fallback value if the trimmed string is empty
    /// - Returns: The trimmed value if not empty, otherwise the fallback
    static func trimmedValueOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmed()
        return trimmed.isEmpty ? fallback : trimmed
    }
    
    /// Returns the trimmed value if not empty, otherwise returns nil.
    /// - Parameter value: The string value to check
    /// - Returns: The trimmed value if not empty, otherwise nil
    static func trimmedValueOrNil(_ value: String) -> String? {
        let trimmed = value.trimmed()
        return trimmed.isEmpty ? nil : trimmed
    }
}


