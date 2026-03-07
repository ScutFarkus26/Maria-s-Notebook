import Foundation
import NaturalLanguage

// MARK: - Student Data Structures

struct StudentData: Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let nickname: String?
}

struct TextReplacement: Sendable {
    let originalText: String
    let replacement: String
}

struct StudentMatchResult: Sendable {
    var exact: Set<UUID>
    var fuzzy: Set<UUID>
    var autoSelect: Set<UUID> // Unique matches that should be auto-selected
    var replacements: [TextReplacement] = [] // Text replacements to apply
}

// MARK: - Student Tagger Actor
// Runs heavy regex/NLP off the main thread to keep typing smooth

actor StudentTagger {
    private let tagger = NLTagger(tagSchemes: [.nameType])

    /// Precomputed name frequency maps for uniqueness checks.
    private struct NameMaps {
        var firstNameCounts: [String: Int] = [:]
        var nicknameCounts: [String: Int] = [:]
        var fullNameCounts: [String: Int] = [:]
        var initialsMap: [String: [UUID]] = [:]
    }

    // MARK: - Identification Logic

    func findStudentMatches(in text: String, studentData: [StudentData]) -> StudentMatchResult {
        var exact = Set<UUID>()
        var fuzzy = Set<UUID>()
        var autoSelect = Set<UUID>()

        guard !text.isEmpty else {
            return StudentMatchResult(exact: exact, fuzzy: fuzzy, autoSelect: autoSelect)
        }

        let haystack = text
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        let lowerText = text.lowercased()
        let nameMaps = buildNameMaps(from: studentData)

        // Phase 1: Authoritative matches (name patterns + initials)
        scanAuthoritativeNamePatterns(studentData, lowerText: lowerText, exact: &exact)
        scanAuthoritativeInitials(studentData, text: text, lowerText: lowerText, exact: &exact)

        // Phase 2: NLTagger token scan for single names / nicknames
        scanNLTaggerTokens(
            in: text, lowerText: lowerText, studentData: studentData,
            exact: &exact, fuzzy: &fuzzy
        )

        // Phase 3: Manual text scan to catch patterns NLTagger misses
        scanManualPatterns(
            studentData: studentData, haystack: haystack, lowerText: lowerText,
            nameMaps: nameMaps, exact: &exact, fuzzy: &fuzzy, autoSelect: &autoSelect
        )

        // Finalize auto-select candidates from Phase 2 exact matches
        computeAutoSelectCandidates(
            exact: exact, studentData: studentData, nameMaps: nameMaps, autoSelect: &autoSelect
        )

        // Generate text replacements for exact matches
        let replacements = generateReplacements(
            for: exact, in: text, studentData: studentData,
            firstNameCounts: nameMaps.firstNameCounts
        )

        return StudentMatchResult(
            exact: exact, fuzzy: fuzzy, autoSelect: autoSelect,
            replacements: replacements
        )
    }

    // MARK: - Phase Helpers

    private func buildNameMaps(from studentData: [StudentData]) -> NameMaps {
        var maps = NameMaps()
        for student in studentData {
            let first = student.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let last = student.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            maps.firstNameCounts[first, default: 0] += 1
            if let nick = student.nickname, !nick.trimmed().isEmpty {
                let nickNorm = nick.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                maps.nicknameCounts[nickNorm, default: 0] += 1
            }
            let full = (first + " " + last).trimmed()
            maps.fullNameCounts[full, default: 0] += 1
            if let fi = first.first, let li = last.first {
                let key = String(fi) + String(li)
                maps.initialsMap[key, default: []].append(student.id)
            }
        }
        return maps
    }

    /// Phase 1A: Scan for full name and "First LastInitial" patterns.
    private func scanAuthoritativeNamePatterns(
        _ studentData: [StudentData], lowerText: String, exact: inout Set<UUID>
    ) {
        for student in studentData {
            let f = student.firstName.lowercased()
            let l = student.lastName.lowercased()
            let firstInitial = student.lastName.prefix(1).lowercased()

            let patterns = [
                "\\b\(f) \(l)\\b",           // "Sara Smith"
                "\\b\(f) \(firstInitial)\\b", // "Sara S"
                "\\b\(f) \(firstInitial)\\.\\b" // "Sara S."
            ]

            for pattern in patterns where containsWithBoundary(source: lowerText, pattern: pattern) {
                exact.insert(student.id)
            }
        }
    }

    /// Phase 1B: Scan for separated initials ("J.D.", "J D") and compact initials ("JD").
    private func scanAuthoritativeInitials(
        _ studentData: [StudentData], text: String, lowerText: String, exact: inout Set<UUID>
    ) {
        // 1. Separated Initials (e.g. "J.D.", "J D", "m.a.") - Case Insensitive
        let separatedPattern = "\\b([a-z])(?:\\.|\\s+)([a-z])\\.?\\b"
        do {
            let regex = try NSRegularExpression(pattern: separatedPattern, options: .caseInsensitive)
            let matches = regex.matches(in: lowerText, range: NSRange(lowerText.startIndex..., in: lowerText))
            for match in matches {
                guard match.numberOfRanges >= 3,
                      let r1 = Range(match.range(at: 1), in: lowerText),
                      let r2 = Range(match.range(at: 2), in: lowerText) else { continue }

                let i1 = String(lowerText[r1])
                let i2 = String(lowerText[r2])

                for student in studentData {
                    if student.firstName.prefix(1).lowercased() == i1 &&
                       student.lastName.prefix(1).lowercased() == i2 {
                        exact.insert(student.id)
                    }
                }
            }
        } catch {
            print("⚠️ [\(#function)] Failed to create regex for separated initials: \(error)")
        }

        // 2. Compact Initials (e.g. "JD", "MA") - Case Sensitive (Strict)
        //    Must be Uppercase to avoid matching "Ma" (Maya) or "to" (Tom O'Neil).
        let compactPattern = "\\b([A-Z])([A-Z])\\b"
        do {
            let regex = try NSRegularExpression(pattern: compactPattern)
            // Scan ORIGINAL text to check for Uppercase
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard match.numberOfRanges >= 3,
                      let r1 = Range(match.range(at: 1), in: text),
                      let r2 = Range(match.range(at: 2), in: text) else { continue }

                let i1 = String(text[r1]).lowercased()
                let i2 = String(text[r2]).lowercased()

                for student in studentData {
                    if student.firstName.prefix(1).lowercased() == i1 &&
                       student.lastName.prefix(1).lowercased() == i2 {
                        exact.insert(student.id)
                    }
                }
            }
        } catch {
            print("⚠️ [\(#function)] Failed to create regex for compact initials: \(error)")
        }
    }

    /// Phase 2: Use NLTagger to scan tokens for single names / nicknames.
    private func scanNLTaggerTokens(
        in text: String, lowerText: String, studentData: [StudentData],
        exact: inout Set<UUID>, fuzzy: inout Set<UUID>
    ) {
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word, scheme: .nameType, options: options
        ) { _, tokenRange in
            let token = String(text[tokenRange])

            var tokenExactCandidates = Set<UUID>()
            var tokenFuzzyCandidates = Set<UUID>()

            for student in studentData {
                if self.isExactMatch(token, student: student) {
                    tokenExactCandidates.insert(student.id)
                } else if self.isFuzzyMatch(token, student: student) {
                    tokenFuzzyCandidates.insert(student.id)
                }
            }

            // Skip if token matches a student already found in Phase 1
            if !exact.isDisjoint(with: tokenExactCandidates) { return true }

            // Skip if text contains a disambiguating pattern for any candidate
            if self.tokenHasDisambiguatingPattern(
                candidates: tokenExactCandidates, studentData: studentData, lowerText: lowerText
            ) {
                return true
            }

            // Ambiguity resolution
            if tokenExactCandidates.count > 1 {
                // Ambiguous (e.g. "Sara" matches 2 Saras) -> Suggest all, Select none
                fuzzy.formUnion(tokenExactCandidates)
                fuzzy.formUnion(tokenFuzzyCandidates)
            } else if tokenExactCandidates.count == 1 {
                exact.formUnion(tokenExactCandidates)
            } else {
                fuzzy.formUnion(tokenFuzzyCandidates)
            }

            return true
        }
    }

    /// Checks whether any candidate has a "First LastInitial" pattern in the text.
    private func tokenHasDisambiguatingPattern(
        candidates: Set<UUID>, studentData: [StudentData], lowerText: String
    ) -> Bool {
        for candidateID in candidates {
            guard let student = studentData.first(where: { $0.id == candidateID }) else { continue }
            let f = student.firstName.lowercased()
            let firstInitial = student.lastName.prefix(1).lowercased()
            let pattern1 = "\\b\(f) \(firstInitial)\\b"
            let pattern2 = "\\b\(f) \(firstInitial)\\.\\b"
            if containsWithBoundary(source: lowerText, pattern: pattern1) ||
               containsWithBoundary(source: lowerText, pattern: pattern2) {
                return true
            }
        }
        return false
    }

    /// Phase 3: Manual text scan to catch patterns NLTagger misses.
    private func scanManualPatterns(
        studentData: [StudentData], haystack: String, lowerText: String,
        nameMaps: NameMaps, exact: inout Set<UUID>, fuzzy: inout Set<UUID>,
        autoSelect: inout Set<UUID>
    ) {
        let disambiguatingFirstNames = buildDisambiguatingFirstNames(studentData, lowerText: lowerText)

        for student in studentData {
            let first = student.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let last = student.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let nick = (student.nickname ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let full = first + " " + last

            // Skip if already found in earlier phases
            if exact.contains(student.id) || fuzzy.contains(student.id) { continue }

            // Nickname word
            if !nick.isEmpty, containsWord(haystack, word: nick) {
                exact.insert(student.id)
                if nameMaps.nicknameCounts[nick] == 1 { autoSelect.insert(student.id) }
                continue
            }
            // First name word
            if containsWord(haystack, word: first) {
                if disambiguatingFirstNames.contains(first) { continue }
                exact.insert(student.id)
                if nameMaps.firstNameCounts[first] == 1 { autoSelect.insert(student.id) }
                continue
            }
            // Full name words
            if containsFirstAndLast(haystack, first: first, last: last) {
                exact.insert(student.id)
                if nameMaps.fullNameCounts[full] == 1 { autoSelect.insert(student.id) }
                continue
            }
            // Compact or punctuated initials
            if let fi = first.first, let li = last.first,
               containsInitials(haystack, firstInitial: fi, lastInitial: li) {
                exact.insert(student.id)
                let key = String(fi) + String(li)
                if let ids = nameMaps.initialsMap[key], ids.count == 1 { autoSelect.insert(student.id) }
                continue
            }
            // First + last initial (e.g., "ashira b" or "ashira b.")
            if containsFirstAndLastInitial(haystack, first: first, lastInitial: last.prefix(1)) {
                exact.insert(student.id)
                continue
            }
        }
    }

    /// Pre-computes which first names have "FirstName LastInitial" patterns in the text.
    private func buildDisambiguatingFirstNames(
        _ studentData: [StudentData], lowerText: String
    ) -> Set<String> {
        var result: Set<String> = []
        for student in studentData {
            let first = student.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let firstInitial = student.lastName.prefix(1).lowercased()
            let pattern1 = "\\b\(first) \(firstInitial)\\b"
            let pattern2 = "\\b\(first) \(firstInitial)\\.\\b"
            if containsWithBoundary(source: lowerText, pattern: pattern1) ||
               containsWithBoundary(source: lowerText, pattern: pattern2) {
                result.insert(first)
            }
        }
        return result
    }

    /// Checks exact matches for uniqueness and marks them as auto-select candidates.
    private func computeAutoSelectCandidates(
        exact: Set<UUID>, studentData: [StudentData], nameMaps: NameMaps,
        autoSelect: inout Set<UUID>
    ) {
        for id in exact {
            guard let student = studentData.first(where: { $0.id == id }) else { continue }
            let first = student.firstName
                .folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let last = student.lastName
                .folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let nick = (student.nickname ?? "")
                .folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let full = (first + " " + last).trimmed()

            if nameMaps.firstNameCounts[first] == 1
                || (!nick.isEmpty && nameMaps.nicknameCounts[nick] == 1)
                || nameMaps.fullNameCounts[full] == 1 {
                autoSelect.insert(id)
            }

            if let fi = first.first, let li = last.first {
                let key = String(fi) + String(li)
                if let ids = nameMaps.initialsMap[key], ids.count == 1 {
                    autoSelect.insert(id)
                }
            }
        }
    }

    // MARK: - Private Helpers (delegate to shared helpers)

    private func containsWithBoundary(source: String, pattern: String) -> Bool {
        PatternMatchHelpers.containsWithBoundary(source: source, pattern: pattern)
    }

    private func containsWord(_ text: String, word: String) -> Bool {
        PatternMatchHelpers.containsWord(text, word: word)
    }

    private func containsFirstAndLastInitial(_ text: String, first: String, lastInitial: Substring) -> Bool {
        PatternMatchHelpers.containsFirstAndLastInitial(text, first: first, lastInitial: lastInitial)
    }

    private func containsFirstAndLast(_ text: String, first: String, last: String) -> Bool {
        PatternMatchHelpers.containsFirstAndLast(text, first: first, last: last)
    }

    private func containsInitials(_ text: String, firstInitial: Character, lastInitial: Character) -> Bool {
        PatternMatchHelpers.containsInitials(text, firstInitial: firstInitial, lastInitial: lastInitial)
    }

    private func isExactMatch(_ token: String, student: StudentData) -> Bool {
        let t = token.lowercased()
        let f = student.firstName.lowercased()
        let n = (student.nickname ?? "").lowercased()

        return t == f || (!n.isEmpty && t == n)
    }

    private func isFuzzyMatch(_ token: String, student: StudentData) -> Bool {
        if token.isFuzzyMatch(to: student.firstName) { return true }
        if let nick = student.nickname, !nick.isEmpty, token.isFuzzyMatch(to: nick) { return true }
        return false
    }
}
