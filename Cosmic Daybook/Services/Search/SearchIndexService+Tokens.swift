import Foundation

// The index's words and the sorted-token lookup, apart from the index itself.
extension SearchIndexService {
    /// First position in `sorted` whose element is not below `value`.
    nonisolated static func lowerBound(of value: String, in sorted: [String]) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    // MARK: - Tokenization

    /// The index's words: case, accents and width folded, so "Zoe" finds
    /// Zoë (bug hunt 2026-10-11 #50). A fixed locale keeps the stored keys the
    /// same whatever the device's language. The snapshot keeps the text, not
    /// these words, so its next load re-tokenizes under this rule; no format
    /// bump is needed.
    nonisolated static func tokenize(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: foldingLocale)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    nonisolated private static let foldingLocale = Locale(identifier: "en_US_POSIX")
}
