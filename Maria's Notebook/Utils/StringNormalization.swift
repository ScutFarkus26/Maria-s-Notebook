import Foundation

/// Shared string normalization utilities.
/// Consolidates duplicate normalization logic used throughout the app.
enum StringNormalization {
    /// Normalizes a component string by trimming, lowercasing, removing diacritics, and collapsing whitespace.
    /// Used for duplicate detection and comparison operations.
    /// - Parameter string: The string to normalize
    /// - Returns: The normalized string
    static func normalizeComponent(_ string: String) -> String {
        // Trim whitespace and newlines
        let trimmed = string.trimmed()
        // Lowercase
        let lowercased = trimmed.lowercased()
        // Remove diacritics
        let noDiacritics = lowercased.folding(options: .diacriticInsensitive, locale: .current)
        // Collapse internal whitespace sequences to a single space
        let components = noDiacritics.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }
}

