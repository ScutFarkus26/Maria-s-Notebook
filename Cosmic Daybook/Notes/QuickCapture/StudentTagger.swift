import Foundation
import NaturalLanguage

// MARK: - CDStudent Data Structures

nonisolated struct StudentData: Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let nickname: String?
}

struct TextReplacement: Sendable {
    let originalText: String
    let replacement: String
    /// Where the tagger found `originalText`, in UTF-16 units of the text it was
    /// given. Quick Note replaces only there, and only while the text there still
    /// reads exactly `originalText`.
    var range: NSRange?
}

struct StudentMatchResult: Sendable {
    var exact: Set<UUID>
    var fuzzy: Set<UUID>
    var autoSelect: Set<UUID> // Unique matches that should be auto-selected
    var replacements: [TextReplacement] = [] // Text replacements to apply
}

// MARK: - CDStudent Tagger Actor
// Runs heavy regex/NLP off the main thread to keep typing smooth.
// The matching rules themselves live in `PatternMatchHelpers`; `StudentTaggerTests`
// pins them with a table of sentences.

actor StudentTagger {
    private let tagger = NLTagger(tagSchemes: [.nameType])

    /// Precomputed name frequency maps for uniqueness checks, keyed by folded names.
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

        let foldedText = FoldedText(text)
        let nameMaps = buildNameMaps(from: studentData)

        // Phase 1: Authoritative matches (full names, "First L", clear initials)
        let disambiguatedFirstNames = scanAuthoritativeNamePatterns(studentData, text: foldedText, exact: &exact)
        scanAuthoritativeInitials(
            studentData, text: foldedText, nameMaps: nameMaps, exact: &exact, fuzzy: &fuzzy
        )

        // Phase 2: NLTagger token scan for single names / nicknames
        scanNLTaggerTokens(
            in: text, studentData: studentData, disambiguatedFirstNames: disambiguatedFirstNames,
            exact: &exact, fuzzy: &fuzzy
        )

        // Phase 3: Manual text scan to catch names NLTagger misses
        scanManualPatterns(
            studentData: studentData, text: foldedText, nameMaps: nameMaps,
            disambiguatedFirstNames: disambiguatedFirstNames,
            exact: &exact, fuzzy: &fuzzy, autoSelect: &autoSelect
        )

        // Finalize auto-select candidates from Phase 1 and 2 exact matches
        computeAutoSelectCandidates(
            exact: exact, studentData: studentData, nameMaps: nameMaps, autoSelect: &autoSelect
        )

        // Generate text replacements for exact matches
        let replacements = generateReplacements(for: exact, in: foldedText, studentData: studentData)

        return StudentMatchResult(
            exact: exact, fuzzy: fuzzy, autoSelect: autoSelect,
            replacements: replacements
        )
    }

    // MARK: - Phase Helpers

    private func buildNameMaps(from studentData: [StudentData]) -> NameMaps {
        var maps = NameMaps()
        for student in studentData {
            let first = student.firstName.folded()
            let last = student.lastName.folded()
            maps.firstNameCounts[first, default: 0] += 1
            if let nick = student.nickname, !nick.trimmed().isEmpty {
                let nickNorm = nick.folded()
                maps.nicknameCounts[nickNorm, default: 0] += 1
            }
            let full = (first + " " + last).trimmed()
            maps.fullNameCounts[full, default: 0] += 1
            if let key = PatternMatchHelpers.initialsKey(first: student.firstName, last: student.lastName) {
                maps.initialsMap[key, default: []].append(student.id)
            }
        }
        return maps
    }

    /// Phase 1A: Full names ("Sara Smith") and "First LastInitial" ("Sara S", "Sara S.").
    /// Returns the folded first names these settle, so a bare "Sara" elsewhere in
    /// the note doesn't also tag the other Sara.
    private func scanAuthoritativeNamePatterns(
        _ studentData: [StudentData], text: FoldedText, exact: inout Set<UUID>
    ) -> Set<String> {
        var disambiguated: Set<String> = []
        for student in studentData {
            let matched = !PatternMatchHelpers.fullNameRanges(
                first: student.firstName, last: student.lastName, in: text
            ).isEmpty || !PatternMatchHelpers.firstAndInitialRanges(
                first: student.firstName, last: student.lastName, in: text
            ).isEmpty
            if matched {
                exact.insert(student.id)
                disambiguated.insert(student.firstName.folded())
            }
        }
        return disambiguated
    }

    /// Phase 1B: Clear initials ("JD", "J.D.", "J D"). Initials two children share
    /// are suggested for both rather than tagged.
    private func scanAuthoritativeInitials(
        _ studentData: [StudentData], text: FoldedText, nameMaps: NameMaps,
        exact: inout Set<UUID>, fuzzy: inout Set<UUID>
    ) {
        let firstNames = Set(nameMaps.firstNameCounts.keys)
        for match in PatternMatchHelpers.initialsMatches(in: text, firstNames: firstNames) {
            guard let ids = nameMaps.initialsMap[match.key] else { continue }
            if ids.count == 1 {
                exact.formUnion(ids)
            } else {
                fuzzy.formUnion(ids.filter { !exact.contains($0) })
            }
        }
    }

    /// Phase 2: Use NLTagger to scan tokens for single names / nicknames.
    private func scanNLTaggerTokens(
        in text: String, studentData: [StudentData], disambiguatedFirstNames: Set<String>,
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

            // Skip if the text names one of these children with a last name or initial
            if disambiguatedFirstNames.contains(token.folded()) { return true }

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

    // Phase 3: Manual text scan for nicknames and first names NLTagger misses.
    // A name two children share is suggested, never tagged.
    // swiftlint:disable:next function_parameter_count
    private func scanManualPatterns(
        studentData: [StudentData], text: FoldedText, nameMaps: NameMaps,
        disambiguatedFirstNames: Set<String>,
        exact: inout Set<UUID>, fuzzy: inout Set<UUID>, autoSelect: inout Set<UUID>
    ) {
        for student in studentData {
            // Skip if already found in earlier phases
            if exact.contains(student.id) || fuzzy.contains(student.id) { continue }

            let first = student.firstName.folded()
            let nick = (student.nickname ?? "").folded()

            // Nickname word
            if !nick.isEmpty, !PatternMatchHelpers.wordRanges(of: nick, in: text).isEmpty {
                if nameMaps.nicknameCounts[nick] == 1 {
                    exact.insert(student.id)
                    autoSelect.insert(student.id)
                } else {
                    fuzzy.insert(student.id)
                }
                continue
            }
            // First name word
            if !PatternMatchHelpers.wordRanges(of: student.firstName, in: text).isEmpty {
                if disambiguatedFirstNames.contains(first) { continue }
                if nameMaps.firstNameCounts[first] == 1 {
                    exact.insert(student.id)
                    autoSelect.insert(student.id)
                } else {
                    fuzzy.insert(student.id)
                }
            }
        }
    }

    /// Checks exact matches for uniqueness and marks them as auto-select candidates.
    private func computeAutoSelectCandidates(
        exact: Set<UUID>, studentData: [StudentData], nameMaps: NameMaps,
        autoSelect: inout Set<UUID>
    ) {
        for id in exact {
            guard let student = studentData.first(where: { $0.id == id }) else { continue }
            let first = student.firstName.folded()
            let last = student.lastName.folded()
            let nick = (student.nickname ?? "").folded()
            let full = (first + " " + last).trimmed()

            if nameMaps.firstNameCounts[first] == 1
                || (!nick.isEmpty && nameMaps.nicknameCounts[nick] == 1)
                || nameMaps.fullNameCounts[full] == 1 {
                autoSelect.insert(id)
            }

            if let key = PatternMatchHelpers.initialsKey(first: student.firstName, last: student.lastName),
               let ids = nameMaps.initialsMap[key], ids.count == 1 {
                autoSelect.insert(id)
            }
        }
    }

    // MARK: - Private Helpers

    private func isExactMatch(_ token: String, student: StudentData) -> Bool {
        let t = token.folded()
        let f = student.firstName.folded()
        let n = (student.nickname ?? "").folded()

        return t == f || (!n.isEmpty && t == n)
    }

    private func isFuzzyMatch(_ token: String, student: StudentData) -> Bool {
        if token.isFuzzyMatch(to: student.firstName) { return true }
        if let nick = student.nickname, !nick.isEmpty, token.isFuzzyMatch(to: nick) { return true }
        return false
    }
}
