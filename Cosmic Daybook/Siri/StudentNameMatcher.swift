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
//  Siri asks which.
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

    /// The students `spoken` could mean, best tier only, in roster order.
    static func matches(for spoken: String, in roster: [Candidate]) -> [Candidate] {
        let words = normalizedWords(spoken)
        guard !words.isEmpty else { return [] }
        let query = words.joined(separator: " ")

        let tiers: [(Candidate) -> Bool] = [
            // "Maya Stone", or a nickname with the last name.
            { fullNames(of: $0).contains(query) },
            // "Maya S", the notebook's short form.
            { shortNames(of: $0).contains(query) },
            // One name on its own: first, nickname or last.
            { words.count == 1 && singleNames(of: $0).contains(query) },
            // The start of a name: "Mir" for Miriam. Three letters at least,
            // so "Al" doesn't match half the class.
            { query.count >= 3 && singleNames(of: $0).contains { $0.hasPrefix(query) } }
        ]
        for tier in tiers {
            let found = roster.filter(tier)
            if !found.isEmpty { return found }
        }
        return closestSoundingMatches(for: words, in: roster)
    }

    // MARK: - Name forms

    private static func fullNames(of candidate: Candidate) -> Set<String> {
        let last = normalized(candidate.lastName)
        return Set(givenNames(of: candidate).map { "\($0) \(last)" })
    }

    private static func shortNames(of candidate: Candidate) -> Set<String> {
        guard let initial = normalized(candidate.lastName).first else { return [] }
        return Set(givenNames(of: candidate).map { "\($0) \(initial)" })
    }

    private static func singleNames(of candidate: Candidate) -> Set<String> {
        givenNames(of: candidate).union([normalized(candidate.lastName)]).subtracting([""])
    }

    /// First name and nickname: the names a child is called by.
    private static func givenNames(of candidate: Candidate) -> Set<String> {
        Set([candidate.firstName, candidate.nickname ?? ""].map(normalized)).subtracting([""])
    }

    // MARK: - Near misses

    /// Siri's spelling of an unusual name is often off by a sound: "Eddie"
    /// for Etty, "Talya" for Talia. The first word heard is compared with
    /// each first name and nickname by `soundKey`, allowing one difference
    /// (two in a long name), and only the closest wins.
    private static func closestSoundingMatches(for words: [String], in roster: [Candidate]) -> [Candidate] {
        guard let heard = words.first.map(soundKey), heard.count >= 3 else { return [] }
        let allowed = heard.count <= 5 ? 1 : 2
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
        return found
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
