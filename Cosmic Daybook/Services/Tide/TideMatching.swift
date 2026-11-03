// TideMatching.swift
// Matching by words: the first run's to-dos that exist on both sides, and
// the children a Tide to-do names.

import Foundation

/// The first run's guesses at which notebook to-dos and Tide actions are the
/// same thing: about ten existed on both sides before the sharing was
/// switched on (the Room Setup orders, check-ins, MAP testing). Danny sees
/// every guess and confirms before anything is linked or sent.
nonisolated enum TideWordMatch {

    /// One guess.
    struct Pair: Equatable, Sendable {
        let notebookID: UUID
        let tideLink: String
        let score: Double
    }

    /// Words that say nothing about what a to-do is.
    private static let fillers: Set<String> = [
        "a", "an", "the", "and", "or", "to", "for", "of", "in", "on", "at", "with", "about", "from", "by",
        "is", "be", "it", "this", "that", "my", "our", "his", "her", "their", "some", "more"
    ]

    /// Two titles count as one to-do from this score up.
    static let threshold = 0.6

    /// A title's words, folded for case and accents, without fillers.
    static func words(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let parts = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return Set(parts.filter { !fillers.contains($0) })
    }

    /// How alike two titles are, 0 to 1: the share of words they have in
    /// common, or, when every word of the shorter is in the longer, at least
    /// 0.8 ("MAP testing" and "Set up MAP testing for the fall").
    static func score(_ lhs: String, _ rhs: String) -> Double {
        let left = words(lhs), right = words(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let shared = Double(left.intersection(right).count)
        let jaccard = shared / Double(left.union(right).count)
        let smaller = min(left.count, right.count)
        let contained = smaller >= 2 && Int(shared) == smaller ? 0.8 : 0
        return max(jaccard, contained)
    }

    /// The best one-to-one guesses at or above `threshold`, best first. A
    /// Tide action already carrying a notebook to-do's `notebook:` line is
    /// that to-do's, whatever its words say.
    static func pairs(notebook: [TideNotebookTodo], tide: [TideAction]) -> [Pair] {
        var candidates: [Pair] = []
        for action in tide {
            guard let link = action.actionLink?.string else { continue }
            for todo in notebook {
                let score = action.notebookID == todo.id ? 1.0 : score(todo.title, action.action)
                if score >= threshold {
                    candidates.append(Pair(notebookID: todo.id, tideLink: link, score: score))
                }
            }
        }
        candidates.sort { $0.score > $1.score }
        var usedTodos = Set<UUID>(), usedLinks = Set<String>()
        var chosen: [Pair] = []
        for pair in candidates where !usedTodos.contains(pair.notebookID) && !usedLinks.contains(pair.tideLink) {
            usedTodos.insert(pair.notebookID)
            usedLinks.insert(pair.tideLink)
            chosen.append(pair)
        }
        return chosen
    }
}

/// Which children a Tide to-do names, for the child's page: her full name,
/// or the classroom's short form ("Maya S", `CDStudent.shortName`), or her
/// bare first name when no other child has it. Two Ettys or two Sarahs make
/// "Etty" and "Sarah" name nobody; "Etty K" still names the one.
///
/// A bare first name names her only as a name is written, with a capital
/// ("Check Maya's map", not "the maya blue paper"), and one that is also an
/// everyday word (Mark, May, Will, Grace, Rose) only on a "For …" line, as
/// the notebook writes it when it sends a to-do: otherwise "Mark attendance
/// sheets" or "Order paper in May" would land on a child's page (bug hunt
/// 2026-11-02 #49).
nonisolated struct TideNameMatcher: Sendable {
    struct Child: Sendable, Equatable {
        let id: UUID
        let firstName: String
        let lastName: String
    }

    private struct Pattern: Sendable {
        let id: UUID
        /// Full name and short form: anywhere, in any case.
        let forms: [String]
        /// The bare first name, when no other child has it.
        let first: String?
        let firstIsEverydayWord: Bool
    }

    private let patterns: [Pattern]

    /// First names that are also everyday words, folded.
    private static let everydayWords: Set<String> = [
        "may", "june", "april", "august", "summer", "autumn", "winter", "dawn", "eve", "noel",
        "mark", "will", "bill", "pat", "sue", "drew", "chase", "grant", "frank", "jack", "rob", "don",
        "grace", "hope", "faith", "joy", "charity", "mercy", "patience", "honor", "liberty", "harmony", "melody",
        "rose", "lily", "ivy", "daisy", "violet", "iris", "holly", "hazel", "olive", "sage", "basil", "heather",
        "ruby", "pearl", "jade", "amber", "crystal", "ginger", "cherry", "penny", "sunny", "sky", "star",
        "river", "brook", "rain", "storm", "eden", "art", "rich", "miles", "reed", "wade", "dale", "glen",
        "lane", "ray", "gene", "carol", "dot", "max", "gray", "grey", "ash", "hunter", "clay", "cliff"
    ]

    init(children: [Child]) {
        func fold(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespaces)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        let firsts = children.map { fold($0.firstName) }
        let shorts = children.map { fold(CDStudent.shortName(firstName: $0.firstName, lastName: $0.lastName)) }
        patterns = children.enumerated().map { index, child in
            var forms: [String] = []
            let full = fold("\(child.firstName) \(child.lastName)")
            if !fold(child.lastName).isEmpty { forms.append(full) }
            let short = shorts[index]
            if short != firsts[index], shorts.filter({ $0 == short }).count == 1 { forms.append(short) }
            let first = firsts[index]
            let unique = !first.isEmpty && firsts.filter({ $0 == first }).count == 1
            return Pattern(id: child.id, forms: forms, first: unique ? first : nil,
                           firstIsEverydayWord: Self.everydayWords.contains(first))
        }
    }

    /// The children `text` names.
    func children(namedIn text: String) -> Set<UUID> {
        let forLines = text.components(separatedBy: .newlines).filter { line in
            line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("for ")
        }.joined(separator: "\n")
        var named = Set<UUID>()
        for pattern in patterns {
            if pattern.forms.contains(where: { Self.contains(text, word: $0) }) {
                named.insert(pattern.id)
            } else if let first = pattern.first {
                let byFirstName = Self.contains(forLines, word: first)
                    || (!pattern.firstIsEverydayWord && Self.contains(text, word: first, capitalized: true))
                if byFirstName { named.insert(pattern.id) }
            }
        }
        return named
    }

    /// Whether `word` appears in `text`, in any case and accents, with no
    /// letter or digit right before or after it, so "Etty K" isn't found in
    /// "Etty Klein"; `capitalized`, only where it starts with a capital.
    private static func contains(_ text: String, word: String, capitalized: Bool = false) -> Bool {
        guard !word.isEmpty else { return false }
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            let before = found.lowerBound == text.startIndex ? nil : text[text.index(before: found.lowerBound)]
            let after = found.upperBound == text.endIndex ? nil : text[found.upperBound]
            let isWordStart = before.map { !$0.isLetter && !$0.isNumber } ?? true
            let isWordEnd = after.map { !$0.isLetter && !$0.isNumber } ?? true
            let isCapital = !capitalized || text[found.lowerBound].isUppercase
            if isWordStart && isWordEnd && isCapital { return true }
            searchRange = found.upperBound..<text.endIndex
        }
        return false
    }
}
