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

    /// Folds the string for comparison: case- and diacritic-insensitive,
    /// trimmed of surrounding whitespace, and lowercased. `locale: nil` keeps
    /// the result independent of the device locale, so the MCP tools and the
    /// screens agree on whether two names match. `"  Café "` → `"cafe"`.
    nonisolated func folded() -> String {
        self.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmed()
            .lowercased()
    }

    /// `folded()` with every run of internal whitespace (newlines included)
    /// collapsed to one space, for keys where `"Great  Lesson\n Two"` and
    /// `"Great Lesson Two"` must be one entry. → `"great lesson two"`.
    nonisolated func foldedKey() -> String {
        self.folded()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
