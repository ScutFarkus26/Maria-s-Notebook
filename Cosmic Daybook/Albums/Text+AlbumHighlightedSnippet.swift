import SwiftUI

// MARK: - Shared snippet highlighting

extension Text {
    /// Renders a snippet with the query terms emphasized.
    static func albumHighlightedSnippet(_ snippet: String, terms: [String]) -> Text {
        var attributed = AttributedString(snippet)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for term in terms where !term.isEmpty {
            var searchStart = snippet.startIndex
            while let range = snippet.range(of: term, options: options,
                                            range: searchStart..<snippet.endIndex) {
                if let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].font = .callout.bold()
                    attributed[attrRange].foregroundColor = .accentColor
                }
                searchStart = range.upperBound
            }
        }
        return Text(attributed)
    }
}
