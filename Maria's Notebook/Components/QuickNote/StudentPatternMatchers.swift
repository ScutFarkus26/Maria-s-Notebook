import Foundation

// MARK: - Pattern Matching Helpers

enum PatternMatchHelpers {
    nonisolated static func containsWithBoundary(source: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            return regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
        } catch {
            print("\u{26a0}\u{fe0f} [\(#function)] Failed to create regex with pattern '\(pattern)': \(error)")
            return false
        }
    }

    nonisolated static func containsWord(_ text: String, word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated static func containsFirstAndLastInitial(_ text: String, first: String, lastInitial: Substring) -> Bool {
        guard !first.isEmpty, let li = lastInitial.first else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: first) + "\\s+" + NSRegularExpression.escapedPattern(for: String(li)) + "\\.?\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated static func containsFirstAndLast(_ text: String, first: String, last: String) -> Bool {
        guard !first.isEmpty, !last.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: first) + "\\s+" + NSRegularExpression.escapedPattern(for: last) + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated static func containsInitials(_ text: String, firstInitial: Character, lastInitial: Character) -> Bool {
        let fi = String(firstInitial).lowercased()
        let li = String(lastInitial).lowercased()
        // Matches: "a b", "a.b.", "ab" with word boundaries
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: fi) + "\\.?\\s*" + NSRegularExpression.escapedPattern(for: li) + "\\.?\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
