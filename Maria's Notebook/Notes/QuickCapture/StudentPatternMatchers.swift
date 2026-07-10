import Foundation
import OSLog

// MARK: - Pattern Matching Helpers

enum PatternMatchHelpers {
    private static let logger = Logger.notes

    nonisolated static func containsWithBoundary(source: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            return regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
        } catch {
            logger.error("[\(#function)] Failed to create regex with pattern '\(pattern)': \(error)")
            return false
        }
    }

    nonisolated static func containsWord(_ text: String, word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated static func containsFirstAndLastInitial(
        _ text: String, first: String, lastInitial: Substring
    ) -> Bool {
        guard !first.isEmpty, let li = lastInitial.first else { return false }
        let escapedFirst = NSRegularExpression.escapedPattern(for: first)
        let escapedLI = NSRegularExpression.escapedPattern(for: String(li))
        let pattern = "\\b" + escapedFirst + "\\s+" + escapedLI + "\\.?\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated static func containsFirstAndLast(
        _ text: String, first: String, last: String
    ) -> Bool {
        guard !first.isEmpty, !last.isEmpty else { return false }
        let escapedFirst = NSRegularExpression.escapedPattern(for: first)
        let escapedLast = NSRegularExpression.escapedPattern(for: last)
        let pattern = "\\b" + escapedFirst + "\\s+" + escapedLast + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated static func containsInitials(
        _ text: String, firstInitial: Character, lastInitial: Character
    ) -> Bool {
        let fi = String(firstInitial).lowercased()
        let li = String(lastInitial).lowercased()
        // Matches: "a b", "a.b.", "ab" with word boundaries
        let escapedFI = NSRegularExpression.escapedPattern(for: fi)
        let escapedLI = NSRegularExpression.escapedPattern(for: li)
        let pattern = "\\b" + escapedFI + "\\.?\\s*" + escapedLI + "\\.?\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
