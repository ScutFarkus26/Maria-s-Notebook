import Foundation
import OSLog

// MARK: - Folded Text

/// A note's text with accents folded away one character at a time ("Zoë" reads as
/// "Zoe"), so a match found in `folded` maps back to the same characters in
/// `original`. Case is kept: the initials rules need to see capitals.
nonisolated struct FoldedText: Sendable {
    let original: String
    let folded: String

    init(_ text: String) {
        original = text
        let characters = text.map { character -> String in
            let folded = String(character).folding(options: .diacriticInsensitive, locale: nil)
            return folded.count == 1 ? folded : String(character)
        }
        let joined = characters.joined()
        // Folding never merges characters in practice; if it ever did, offsets
        // would no longer line up, so match on the text as typed instead.
        folded = joined.count == text.count ? joined : text
    }

    /// The range in `original` covering the same characters as `range` in `folded`.
    func originalRange(_ range: Range<String.Index>) -> Range<String.Index> {
        let lower = folded.distance(from: folded.startIndex, to: range.lowerBound)
        let length = folded.distance(from: range.lowerBound, to: range.upperBound)
        let start = original.index(original.startIndex, offsetBy: lower)
        return start..<original.index(start, offsetBy: length)
    }

    /// The text she typed for `range` (a range in `folded`).
    func typed(_ range: Range<String.Index>) -> String {
        String(original[originalRange(range)])
    }
}

/// Two-letter initials found in a note ("JD", "J.D.", "J D").
nonisolated struct InitialsMatch: Sendable {
    /// Where the initials are in the original text, without a period after the
    /// second letter ("J.D." → "J.D"), so the period she typed stays.
    let range: Range<String.Index>
    /// The two letters, lowercased and folded ("jd").
    let key: String
}

// MARK: - Pattern Matching Helpers

/// The name tagger's matching rules, shared by Quick Note, the note editor's
/// Expand Initials and Format Names. Names and text are both accent-folded and
/// matched case-insensitively, except where a rule below needs capitals.
enum PatternMatchHelpers {
    nonisolated private static let logger = Logger.notes

    /// Whitespace within a line: a name and its initial don't span a line break.
    nonisolated private static let inlineSpace = "[^\\S\\r\\n]"

    /// Dotted pairs that are abbreviations, never initials ("10 a.m.", "e.g.", "P.E.").
    nonisolated private static let dottedAbbreviations: Set<String> = [
        "am", "pm", "eg", "ie", "us", "uk", "dc", "pe", "tv", "ps"
    ]

    /// Capital pairs that are abbreviations, never initials ("OK", "PE", "TV").
    nonisolated private static let capitalAbbreviations: Set<String> = dottedAbbreviations.union([
        "ok", "id", "ot", "pt", "hr", "ai", "ap", "ad", "bc", "ft", "lb", "oz", "mr", "ms", "dr", "st", "vs"
    ])

    /// A name folded the way `FoldedText` folds the note: accents gone, case kept.
    nonisolated static func foldedName(_ name: String) -> String {
        name.folding(options: .diacriticInsensitive, locale: nil).trimmed()
    }

    /// Every whole-word occurrence of `name` ("Maya" in "Maya's", not in "Mayan").
    nonisolated static func wordRanges(of name: String, in text: FoldedText) -> [Range<String.Index>] {
        let name = foldedName(name)
        guard !name.isEmpty else { return [] }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
        return matches(of: pattern, in: text).compactMap { match in
            Range(match.range, in: text.folded).map(text.originalRange)
        }
    }

    /// Every "First Last" ("Maya Smith").
    nonisolated static func fullNameRanges(first: String, last: String, in text: FoldedText) -> [Range<String.Index>] {
        let first = foldedName(first)
        let last = foldedName(last)
        guard !first.isEmpty, !last.isEmpty else { return [] }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: first) + inlineSpace + "+"
            + NSRegularExpression.escapedPattern(for: last) + "\\b"
        return matches(of: pattern, in: text).compactMap { match in
            Range(match.range, in: text.folded).map(text.originalRange)
        }
    }

    /// Every "First L" or "First L." ("Maya S", "Sarah M's"). The range ends at the
    /// initial, leaving any period in the text. A lone "a", "i" or "I" with no
    /// period is a word, never an initial: "gave Leo a pencil", "Sarah I think".
    nonisolated static func firstAndInitialRanges(
        first: String, last: String, in text: FoldedText
    ) -> [Range<String.Index>] {
        let first = foldedName(first)
        guard !first.isEmpty, let initial = foldedName(last).first else { return [] }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: first) + inlineSpace + "+("
            + NSRegularExpression.escapedPattern(for: String(initial)) + ")(?!\\w)(\\.?)"
        return matches(of: pattern, in: text).compactMap { match in
            guard let whole = Range(match.range, in: text.folded),
                  let letter = Range(match.range(at: 1), in: text.folded),
                  let period = Range(match.range(at: 2), in: text.folded) else { return nil }
            let typedLetter = String(text.folded[letter])
            if period.isEmpty, typedLetter == "a" || typedLetter.lowercased() == "i" { return nil }
            return text.originalRange(whole.lowerBound..<letter.upperBound)
        }
    }

    /// Two-letter initials that clearly are initials: two capitals ("JD", "J D"), a
    /// period between the letters ("J.D", "j.d."), or capitals with both periods
    /// ("J. D."). Ordinary words ("is", "to"), abbreviations ("a.m.", "e.g.", "OK",
    /// "PE") and a sentence break ("Maya S. I think", "Maya S I think") never count.
    /// Spaced capitals are the loosest form, so they don't count with an "A" or "I"
    /// in them ("A B" in a note about letters, "Maya S A great day"), or when the
    /// first letter is a short name's initial: pass the roster's first names
    /// (`folded()`) as `firstNames` and "Maya S T" leaves "S T" alone.
    nonisolated static func initialsMatches(
        in text: FoldedText, firstNames: Set<String> = []
    ) -> [InitialsMatch] {
        let pattern = "\\b([A-Za-z])(\\.?)(" + inlineSpace + "*)([A-Za-z])(?!\\w)(\\.?)"
        return matches(of: pattern, in: text, caseInsensitive: false).compactMap { match in
            guard let r1 = Range(match.range(at: 1), in: text.folded),
                  let firstPeriod = Range(match.range(at: 2), in: text.folded),
                  let space = Range(match.range(at: 3), in: text.folded),
                  let r2 = Range(match.range(at: 4), in: text.folded),
                  let lastPeriod = Range(match.range(at: 5), in: text.folded) else { return nil }
            let firstLetter = String(text.folded[r1])
            let lastLetter = String(text.folded[r2])
            let key = (firstLetter + lastLetter).lowercased()
            let capitals = firstLetter == firstLetter.uppercased() && lastLetter == lastLetter.uppercased()

            switch (firstPeriod.isEmpty, space.isEmpty) {
            case (false, true): // "J.D", "j.d."
                guard !dottedAbbreviations.contains(key) else { return nil }
            case (false, false): // "J. D."
                guard capitals, !lastPeriod.isEmpty, !dottedAbbreviations.contains(key) else { return nil }
            case (true, false): // "J D"
                guard capitals, !["A", "I"].contains(firstLetter), !["A", "I"].contains(lastLetter),
                      !capitalAbbreviations.contains(key),
                      !followsFirstName(text.folded[..<r1.lowerBound], firstNames: firstNames) else { return nil }
            case (true, true): // "JD"
                guard capitals, !capitalAbbreviations.contains(key) else { return nil }
            }
            return InitialsMatch(range: text.originalRange(r1.lowerBound..<r2.upperBound), key: key)
        }
    }

    /// Whether `prefix` ends with one of `firstNames` and a space, so the letter
    /// after it is that name's last initial ("Maya " before "S").
    nonisolated private static func followsFirstName(_ prefix: Substring, firstNames: Set<String>) -> Bool {
        guard !firstNames.isEmpty, prefix.last?.isWhitespace == true else { return false }
        let words = String(prefix).folded()
        return firstNames.contains { name in
            guard !name.isEmpty, words.hasSuffix(name) else { return false }
            return words.dropLast(name.count).last.map { !$0.isLetter } ?? true
        }
    }

    /// The lowercased, folded initials key for a child ("Jonah", "Davis" → "jd").
    nonisolated static func initialsKey(first: String, last: String) -> String? {
        guard let fi = foldedName(first).first, let li = foldedName(last).first else { return nil }
        return (String(fi) + String(li)).lowercased()
    }

    nonisolated private static func matches(
        of pattern: String, in text: FoldedText, caseInsensitive: Bool = true
    ) -> [NSTextCheckingResult] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
            return regex.matches(in: text.folded, range: NSRange(text.folded.startIndex..., in: text.folded))
        } catch {
            logger.error("[\(#function)] Failed to create regex with pattern '\(pattern)': \(error)")
            return []
        }
    }
}
