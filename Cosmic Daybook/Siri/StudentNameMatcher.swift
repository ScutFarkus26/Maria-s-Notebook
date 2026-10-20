//
//  StudentNameMatcher.swift
//  Cosmic Daybook
//
//  Turns a name Siri heard (or someone typed into Shortcuts) into the students
//  it could mean. Shared with Daybook Assistant.
//
//  Spoken names arrive in every shape: "Maya", "Maya Stone", "Maya S", a
//  nickname, or a near miss ("Eddie" for Etty). The tiers below run strictest
//  first and stop at the first one that finds anyone, so an exact "Sarah
//  Klein" never drags in Sarah Adler, while a bare "Sarah" returns both and
//  Siri asks which. The exact tiers cover former children too before any
//  sound-alike is tried. A tier also brings in the names spelled
//  differently that sound just the same (Sara for Sarah, `soundFolded`), so
//  Siri asks which rather than going by the spelling the recognizer wrote.
//

import Foundation

nonisolated enum StudentNameMatcher {

    /// The name parts of one student, detached from Core Data.
    struct Candidate: Equatable, Sendable {
        let id: UUID
        let firstName: String
        let lastName: String
        let nickname: String?
    }

    /// The students `spoken` could mean among the class (`current`) and the
    /// children who have left (`former`, read only when it's needed). Every
    /// exact tier (full name, short form, one name, the start of a name)
    /// runs over the class and then over former children before any
    /// sound-alike, which tries the class first too: "Mark Leah here" finds
    /// Leah, who has left (and is refused by name), never Lea in the class,
    /// whose name only sounds like it (bug hunt 2026-10-17, #4).
    static func matches(
        for spoken: String, current: [Candidate], former: () -> [Candidate]
    ) -> [Candidate] {
        let words = normalizedWords(spoken)
        guard !words.isEmpty else { return [] }
        let exact = exactMatches(for: words, in: current)
        if !exact.isEmpty { return exact }
        let currentIDs = Set(current.map(\.id))
        let others = former().filter { !currentIDs.contains($0.id) }
        let formerExact = exactMatches(for: words, in: others)
        if !formerExact.isEmpty { return formerExact }
        let near = closestSoundingMatches(for: words, in: current)
        return near.isEmpty ? closestSoundingMatches(for: words, in: others) : near
    }

    /// The students `spoken` could mean in one list, best tier only, in
    /// roster order.
    static func matches(for spoken: String, in roster: [Candidate]) -> [Candidate] {
        matches(for: spoken, current: roster, former: { [] })
    }

    /// The exact tiers, strictest first; the first that finds anyone wins.
    ///
    /// A tier also returns the names that sound just the same as the one
    /// heard but are spelled differently (`soundFolded`), so "Sarah" with
    /// Sara and Sarah in the class returns both and Siri asks which: the
    /// spelling is only the recognizer's guess (bug hunt 2026-10-20, #26).
    /// Such a name settles a tier on its own only with the last name or its
    /// initial ("Sarah Klein" finds Sara Klein). A first name that only
    /// sounds alike never does: "Leah", who has left, is never marked as Lea
    /// in the class (bug hunt 2026-10-17, #4).
    private static func exactMatches(for words: [String], in roster: [Candidate]) -> [Candidate] {
        let spelled = tiers(for: words, fold: { $0 }, withPrefix: true)
        let soundAlike = tiers(for: words.map(soundFolded), fold: soundFolded, withPrefix: false)
        for (index, (tier, alike)) in zip(spelled, soundAlike).enumerated() {
            // The full name and the short form carry the last name.
            let alikeSettles = index < 2
            guard roster.contains(where: tier) || (alikeSettles && roster.contains(where: alike)) else { continue }
            return roster.filter { tier($0) || alike($0) }
        }
        return []
    }

    /// The exact tiers for `words`, every name form passed through `fold`.
    /// Without `withPrefix` the last tier finds no one: "Leah" folded to
    /// "lea" would start Leandra.
    private static func tiers(
        for words: [String], fold: @escaping (String) -> String, withPrefix: Bool
    ) -> [(Candidate) -> Bool] {
        let query = words.joined(separator: " ")
        return [
            // "Maya Stone", or a nickname with the last name.
            { fullNames(of: $0, fold).contains(query) },
            // "Maya S", the notebook's short form.
            { shortNames(of: $0, fold).contains(query) },
            // One name on its own: first, nickname or last.
            { words.count == 1 && singleNames(of: $0, fold).contains(query) },
            // The start of a name: "Mir" for Miriam. Three letters at least,
            // so "Al" doesn't match half the class.
            { withPrefix && query.count >= 3 && singleNames(of: $0, fold).contains { $0.hasPrefix(query) } }
        ]
    }

    // MARK: - Name forms

    private static func fullNames(of candidate: Candidate, _ fold: (String) -> String) -> Set<String> {
        let last = fold(normalized(candidate.lastName))
        return Set(givenNames(of: candidate, fold).map { "\($0) \(last)" })
    }

    private static func shortNames(of candidate: Candidate, _ fold: (String) -> String) -> Set<String> {
        guard let initial = normalized(candidate.lastName).first else { return [] }
        return Set(givenNames(of: candidate, fold).map { "\($0) \(initial)" })
    }

    private static func singleNames(of candidate: Candidate, _ fold: (String) -> String) -> Set<String> {
        givenNames(of: candidate, fold).union([fold(normalized(candidate.lastName))]).subtracting([""])
    }

    /// First name and nickname: the names a child is called by.
    private static func givenNames(
        of candidate: Candidate, _ fold: (String) -> String = { $0 }
    ) -> Set<String> {
        Set([candidate.firstName, candidate.nickname ?? ""].map { fold(normalized($0)) }).subtracting([""])
    }

    // MARK: - Near misses

    /// Siri's spelling of an unusual name is often off by a sound: "Eddie"
    /// for Etty, "Talya" for Talia. The first word heard is compared with
    /// each first name and nickname by `soundKey`, and only the closest win.
    /// A name that sounds just the same always counts. A near miss (one
    /// difference, two in a long name) counts only on a sound key longer
    /// than three letters, and never alone: whether Siri asks before taking
    /// a single answer isn't documented, so "Ari" heard for Avi would mark
    /// Avi. Two near misses come back together, and Siri asks which.
    private static func closestSoundingMatches(for words: [String], in roster: [Candidate]) -> [Candidate] {
        guard let heard = words.first.map(soundKey), heard.count >= 3 else { return [] }
        let allowed = heard.count <= 3 ? 0 : heard.count <= 5 ? 1 : 2
        var best = Int.max
        var found: [Candidate] = []
        for candidate in roster {
            let distance = givenNames(of: candidate)
                .map { editDistance(heard, soundKey($0)) }
                .min() ?? Int.max
            guard distance <= allowed else { continue }
            if distance < best {
                best = distance
                found = [candidate]
            } else if distance == best {
                found.append(candidate)
            }
        }
        // A lone near miss is a guess.
        return best > 0 && found.count == 1 ? [] : found
    }

    /// A rough spelling of how a name sounds: letters that sound alike merge
    /// (d/t, b/p, g/k, v/f, z/s, c/q/k, a non-initial y is i), "ph" is f, a
    /// final "ie"/"ee" is i, and doubled letters collapse.
    /// "Eddie" and "Etty" both become "eti".
    static func soundKey(_ name: String) -> String {
        let merged: [Character: Character] = [
            "d": "t", "b": "p", "g": "k", "v": "f", "z": "s", "c": "k", "q": "k"
        ]
        var text = normalized(name).replacingOccurrences(of: " ", with: "")
        text = text.replacingOccurrences(of: "ph", with: "f")
        var letters = text.enumerated().map { index, letter -> Character in
            if letter == "y", index > 0 { return "i" }
            return merged[letter] ?? letter
        }
        if letters.count > 2, letters.suffix(2) == ["i", "e"] || letters.suffix(2) == ["e", "e"] {
            letters.removeLast(2)
            letters.append("i")
        }
        var key = ""
        for letter in letters where letter != key.last {
            key.append(letter)
        }
        return key
    }

    /// Levenshtein distance between two short strings.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Normalizing

    /// A name as it sounds when spelled either way, word by word: a final
    /// "h" after a vowel is dropped, so Sarah and Sara, Noah and Noa, Rivkah
    /// and Rivka read the same, and Beth and Bet don't. Normalized as
    /// `normalized` ("Sárah" → "sara"). The phone grids tell such names
    /// apart as they do shared ones (`AttendanceGridNames`).
    static func soundFolded(_ name: String) -> String {
        normalizedWords(name).map { word in
            guard word.count > 2, word.hasSuffix("h"),
                  let before = word.dropLast().last, "aeiou".contains(before) else { return word }
            return String(word.dropLast())
        }.joined(separator: " ")
    }

    /// Lowercased, accents folded, punctuation dropped ("Maya S." → "maya s").
    static func normalized(_ text: String) -> String {
        normalizedWords(text).joined(separator: " ")
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }
    }
}
