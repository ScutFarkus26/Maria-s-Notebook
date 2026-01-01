import Foundation

/// String extensions for common operations
extension String {
    /// Trims whitespace and newlines from the string
    /// - Returns: A new string with leading and trailing whitespace/newlines removed
    func trimmed() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Normalizes a name string for duplicate detection and comparison
    /// - Returns: A normalized string (lowercased, trimmed, single-spaced)
    func normalizedNameKey() -> String {
        let components = self.lowercased()
            .trimmed()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }
}

