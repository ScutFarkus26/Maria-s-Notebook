import Foundation

/// String extensions for common operations
extension String {
    /// Trims whitespace and newlines from the string
    /// - Returns: A new string with leading and trailing whitespace/newlines removed
    nonisolated func trimmed() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Normalizes a name string for duplicate detection and comparison
    /// - Returns: A normalized string (lowercased, trimmed, single-spaced)
    nonisolated func normalizedNameKey() -> String {
        let components = self.lowercased()
            .trimmed()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }

    /// Normalizes a string for case-insensitive comparison and search operations
    /// - Returns: A trimmed and lowercased string
    nonisolated func normalizedForComparison() -> String {
        self.trimmed().lowercased()
    }
    
    /// Tokenizes the string by splitting on spaces and filtering empty results
    /// - Returns: An array of non-empty, trimmed tokens
    nonisolated func tokenize() -> [String] {
        split(separator: " ")
            .map { String($0).trimmed() }
            .filter { !$0.isEmpty }
    }
}
