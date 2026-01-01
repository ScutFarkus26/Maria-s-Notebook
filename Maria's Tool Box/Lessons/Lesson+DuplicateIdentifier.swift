import Foundation
import SwiftData

extension Lesson {
    /// A computed property that returns a normalized identifier string
    /// used to detect duplicates in imports and elsewhere.
    var duplicateIdentifier: String {
        let normalizedName = normalizeComponent(name)
        let normalizedSubject = normalizeComponent(subject)
        let normalizedGroup = normalizeComponent(group)
        return [normalizedName, normalizedSubject, normalizedGroup].joined(separator: "|")
    }
}

private func normalizeComponent(_ string: String) -> String {
    // Trim whitespace and newlines
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    // Lowercase
    let lowercased = trimmed.lowercased()
    // Remove diacritics
    let noDiacritics = lowercased.folding(options: .diacriticInsensitive, locale: .current)
    // Collapse internal whitespace sequences to a single space
    let components = noDiacritics.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
    return components.joined(separator: " ")
}
