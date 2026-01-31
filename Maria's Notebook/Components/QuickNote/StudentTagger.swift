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
    
    // MARK: - Text Formatting (Deterministic)
    
    func formatStudentNames(in text: String, studentData: [StudentData]) -> String {
        var resultText = text
        
        struct SearchTerm {
            let term: String
            let replacement: String
        }
        
        var terms: [SearchTerm] = []
        
        for student in studentData {
            let lastInitial = student.lastName.first.map { String($0) } ?? ""
            let replacement = "\(student.firstName) \(lastInitial)."
            
            // Full Name
            let fullName = "\(student.firstName) \(student.lastName)".lowercased()
            terms.append(SearchTerm(term: fullName, replacement: replacement))
            
            // First Name
            terms.append(SearchTerm(term: student.firstName.lowercased(), replacement: replacement))
            
            // Nickname
            if let nick = student.nickname, !nick.isEmpty {
                terms.append(SearchTerm(term: nick.lowercased(), replacement: replacement))
            }
        }
        
        // Sort by length descending to handle overlapping names
        terms.sort { $0.term.count > $1.term.count }
        
        // Perform Replacement
        for searchTerm in terms {
            let escapedTerm = NSRegularExpression.escapedPattern(for: searchTerm.term)
            let pattern = "\\b\(escapedTerm)\\b"
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(resultText.startIndex..<resultText.endIndex, in: resultText)
                resultText = regex.stringByReplacingMatches(in: resultText, options: [], range: range, withTemplate: searchTerm.replacement)
            }
        }
        
        return resultText
    }

    // MARK: - Identification Logic
    
    func findStudentMatches(in text: String, studentData: [StudentData]) -> StudentMatchResult {
        var exact = Set<UUID>()
        var fuzzy = Set<UUID>()
        var autoSelect = Set<UUID>()
        var replacements: [TextReplacement] = []
        
        guard !text.isEmpty else {
            return StudentMatchResult(exact: exact, fuzzy: fuzzy, autoSelect: autoSelect, replacements: replacements)
        }
        
        // Normalize the full text for manual scanning (Pass 2)
        let haystack = text
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        
        let lowerText = text.lowercased()
        
        // Precompute name maps for uniqueness checks
        var firstNameCounts: [String: Int] = [:]
        var nicknameCounts: [String: Int] = [:]
        var fullNameCounts: [String: Int] = [:]
        var initialsMap: [String: [UUID]] = [:]
        
        for student in studentData {
            let first = student.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let last = student.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            firstNameCounts[first, default: 0] += 1
            if let nick = student.nickname, !nick.trimmed().isEmpty {
                let nickNorm = nick.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                nicknameCounts[nickNorm, default: 0] += 1
            }
            let full = (first + " " + last).trimmed()
            fullNameCounts[full, default: 0] += 1
            if let fi = first.first, let li = last.first {
                let key = String(fi) + String(li)
                initialsMap[key, default: []].append(student.id)
            }
        }
        
        // PHASE 1: Scan for "Authoritative" Matches
        // A. Name Patterns (Full Name, First + Initial)
        for student in studentData {
            let f = student.firstName.lowercased()
            let l = student.lastName.lowercased()
            let firstInitial = student.lastName.prefix(1).lowercased()
            
            let patterns = [
                "\\b\(f) \(l)\\b",           // "Sara Smith"
                "\\b\(f) \(firstInitial)\\b", // "Sara S"
                "\\b\(f) \(firstInitial)\\.\\b" // "Sara S."
            ]
            
            for pattern in patterns {
                if self.containsWithBoundary(source: lowerText, pattern: pattern) {
                    exact.insert(student.id)
                }
            }
        }
        
        // B. Initials Patterns
        // 1. Separated Initials (e.g. "J.D.", "J D", "m.a.") - Case Insensitive
        //    Must have a dot or space between letters.
        let separatedPattern = "\\b([a-z])(?:\\.|\\s+)([a-z])\\.?\\b"
        if let regex = try? NSRegularExpression(pattern: separatedPattern, options: .caseInsensitive) {
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
        }
        
        // 2. Compact Initials (e.g. "JD", "MA") - Case Sensitive (Strict)
        //    Must be Uppercase to avoid matching "Ma" (Maya) or "to" (Tom O'Neil).
        let compactPattern = "\\b([A-Z])([A-Z])\\b"
        if let regex = try? NSRegularExpression(pattern: compactPattern) {
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
        }
        
        // PHASE 2: Token Scan (NLTagger) for Single Names / Nicknames
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
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
            
            // CONFLICT RESOLUTION:
            // If this token matches a student already found in Phase 1 (e.g. "Sara" part of "Sara Z."),
            // we discard it to prevent "Sara Z." from also triggering "Sara Adams".
            // We check if any of the candidates for this token are already in the `exact` set.
            if !exact.isDisjoint(with: tokenExactCandidates) {
                return true
            }
            
            // ENHANCED CONFLICT RESOLUTION:
            // Check if the text contains a disambiguating pattern (like "First LastInitial") for
            // any student matching this token. If so, skip this token entirely to avoid adding
            // standalone first name matches when a more specific pattern exists.
            var hasDisambiguatingPattern = false
            for candidateID in tokenExactCandidates {
                if let student = studentData.first(where: { $0.id == candidateID }) {
                    let f = student.firstName.lowercased()
                    let firstInitial = student.lastName.prefix(1).lowercased()
                    // Check if text contains "FirstName LastInitial" or "FirstName LastInitial."
                    let pattern1 = "\\b\(f) \(firstInitial)\\b"
                    let pattern2 = "\\b\(f) \(firstInitial)\\.\\b"
                    if self.containsWithBoundary(source: lowerText, pattern: pattern1) ||
                       self.containsWithBoundary(source: lowerText, pattern: pattern2) {
                        hasDisambiguatingPattern = true
                        break
                    }
                }
            }
            // If we found a disambiguating pattern, skip this token entirely
            if hasDisambiguatingPattern {
                return true
            }
            
            // AMBIGUITY LOGIC:
            if tokenExactCandidates.count > 1 {
                // Ambiguous (e.g. "Sara" matches 2 Saras) -> Suggest all, Select none
                fuzzy.formUnion(tokenExactCandidates)
                fuzzy.formUnion(tokenFuzzyCandidates)
            } else if tokenExactCandidates.count == 1 {
                // Clarified -> Select it
                exact.formUnion(tokenExactCandidates)
            } else {
                // No exact match -> Suggest fuzzies
                fuzzy.formUnion(tokenFuzzyCandidates)
            }
            
            return true
        }
        
        // PHASE 3: Manual scan of the full text to catch patterns not tagged by NLTagger
        // This is the "Pass 2" logic from UnifiedNoteEditor that catches edge cases
        
        // Pre-compute: Check if any first names have disambiguating patterns (FirstName LastInitial)
        // If "Sarah Z" exists, we shouldn't add standalone "Sarah" matches
        var firstNamesWithDisambiguatingPatterns: Set<String> = []
        for student in studentData {
            let first = student.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let firstInitial = student.lastName.prefix(1).lowercased()
            let pattern1 = "\\b\(first) \(firstInitial)\\b"
            let pattern2 = "\\b\(first) \(firstInitial)\\.\\b"
            if containsWithBoundary(source: lowerText, pattern: pattern1) ||
               containsWithBoundary(source: lowerText, pattern: pattern2) {
                firstNamesWithDisambiguatingPatterns.insert(first)
            }
        }
        
        for student in studentData {
            let first = student.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let last = student.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let nick = (student.nickname ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let full = first + " " + last
            
            // Skip if already found in earlier phases
            if exact.contains(student.id) || fuzzy.contains(student.id) {
                continue
            }
            
            // Nickname word
            if !nick.isEmpty, containsWord(haystack, word: nick) {
                exact.insert(student.id)
                if nicknameCounts[nick] == 1 {
                    autoSelect.insert(student.id)
                }
                continue
            }
            // First name word
            if containsWord(haystack, word: first) {
                // If there's a disambiguating pattern (like "Sarah Z") for this first name,
                // skip adding standalone first name matches entirely
                if firstNamesWithDisambiguatingPatterns.contains(first) {
                    continue
                }
                
                // Only add standalone first name if it's unique
                exact.insert(student.id)
                if firstNameCounts[first] == 1 {
                    autoSelect.insert(student.id)
                }
                continue
            }
            // Full name words
            if containsFirstAndLast(haystack, first: first, last: last) {
                exact.insert(student.id)
                if fullNameCounts[full] == 1 {
                    autoSelect.insert(student.id)
                }
                continue
            }
            // Compact or punctuated initials
            if let fi = first.first, let li = last.first, containsInitials(haystack, firstInitial: fi, lastInitial: li) {
                exact.insert(student.id)
                let key = String(fi) + String(li)
                if let ids = initialsMap[key], ids.count == 1 {
                    autoSelect.insert(student.id)
                }
                continue
            }
            // First + last initial (e.g., "ashira b" or "ashira b.")
            if containsFirstAndLastInitial(haystack, first: first, lastInitial: last.prefix(1)) {
                exact.insert(student.id)
                continue
            }
        }
        
        // Also check for auto-select candidates from Phase 2 (unique matches)
        for id in exact {
            // Check if this exact match is unique for its name pattern
            if let student = studentData.first(where: { $0.id == id }) {
                let first = student.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                let last = student.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                let nick = (student.nickname ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
                let full = (first + " " + last).trimmed()
                
                if firstNameCounts[first] == 1 || (!nick.isEmpty && nicknameCounts[nick] == 1) || fullNameCounts[full] == 1 {
                    autoSelect.insert(id)
                }
                
                // Check initials
                if let fi = first.first, let li = last.first {
                    let key = String(fi) + String(li)
                    if let ids = initialsMap[key], ids.count == 1 {
                        autoSelect.insert(id)
                    }
                }
            }
        }
        
        // Generate text replacements for exact matches
        replacements = generateReplacements(for: exact, in: text, studentData: studentData, firstNameCounts: firstNameCounts)
        
        return StudentMatchResult(exact: exact, fuzzy: fuzzy, autoSelect: autoSelect, replacements: replacements)
    }
    
    // MARK: - Replacement Generation
    
    private func generateReplacements(
        for exactMatches: Set<UUID>,
        in text: String,
        studentData: [StudentData],
        firstNameCounts: [String: Int]
    ) -> [TextReplacement] {
        var replacements: [TextReplacement] = []
        
        // Track what we've already seen to avoid duplicate replacements
        var seenReplacements: Set<String> = []
        
        for studentID in exactMatches {
            guard let student = studentData.first(where: { $0.id == studentID }) else { continue }
            
            let first = student.firstName
            let last = student.lastName
            let firstLower = first.lowercased()
            let lastLower = last.lowercased()
            let firstInitial = last.prefix(1).lowercased()
            let nick = (student.nickname ?? "").trimmed()
            
            // Determine replacement text (display name format)
            let replacement: String
            if firstNameCounts[firstLower] ?? 0 > 1 {
                // Multiple students with same first name - use "FirstName LastInitial."
                replacement = "\(first) \(firstInitial.uppercased())."
            } else {
                // Unique first name - use just first name
                replacement = first
            }
            
            // Find and replace patterns in order of specificity (most specific first)
            var processedRanges: [NSRange] = []
            
            // Helper to check if matched text is already in replacement format
            // This prevents replacing "Sarah Z." with "Sarah Z." (which would add more periods)
            let isAlreadyReplaced: (String) -> Bool = { matchedText in
                let matchedTrimmed = matchedText.trimmed()
                let replacementTrimmed = replacement.trimmed()
                
                // Exact match (case-insensitive)
                if matchedTrimmed.lowercased() == replacementTrimmed.lowercased() {
                    return true
                }
                
                // For replacements that end with period (like "Sarah Z."), check if the matched text
                // already follows that exact format - if so, don't replace it
                if replacementTrimmed.hasSuffix(".") {
                    // Check if matched text is "FirstName LastInitial." format
                    let expectedPattern = "\(firstLower) \(firstInitial)\\."
                    if let regex = try? NSRegularExpression(pattern: "^\(expectedPattern)$", options: .caseInsensitive) {
                        let range = NSRange(matchedText.startIndex..., in: matchedText)
                        if regex.firstMatch(in: matchedText, options: [], range: range) != nil {
                            return true
                        }
                    }
                }
                
                return false
            }
            
            // 1. Full name: "Ora Pardo"
            let fullNamePattern = "\\b\(NSRegularExpression.escapedPattern(for: firstLower))\\s+\(NSRegularExpression.escapedPattern(for: lastLower))\\b"
            if let regex = try? NSRegularExpression(pattern: fullNamePattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if !processedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                        if let range = Range(match.range, in: text) {
                            let matchedText = String(text[range])
                            // Skip if already in replacement format
                            if !isAlreadyReplaced(matchedText) {
                                replacements.append(TextReplacement(originalText: matchedText, replacement: replacement))
                                processedRanges.append(match.range)
                            }
                        }
                    }
                }
            }
            
            // 2. First + Last Initial: "Ora P" or "Ora P."
            // Only match if we need to replace it (don't match if already in replacement format)
            // If replacement format is "FirstName LastInitial.", don't match text that already ends with period
            // FIX: Use (?:\\.|\\b) instead of \\.?\\b to ensure we consume the period if present,
            // preventing partial matches on "Sarah M." (which would otherwise match "Sarah M" and cause double periods)
            let firstLastInitialPattern = "\\b\(NSRegularExpression.escapedPattern(for: firstLower))\\s+\(NSRegularExpression.escapedPattern(for: firstInitial))(?:\\.|\\b)"
            if let regex = try? NSRegularExpression(pattern: firstLastInitialPattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if !processedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                        if let range = Range(match.range, in: text) {
                            let matchedText = String(text[range]).trimmed()
                            
                            // Critical check: if replacement format includes a period, and the matched text
                            // already ends with a period, and it matches the replacement format, skip it entirely
                            if replacement.hasSuffix(".") && matchedText.hasSuffix(".") {
                                // Build what the replacement format would look like
                                let expectedFormat = "\(first) \(firstInitial.uppercased())."
                                let expectedLower = expectedFormat.lowercased()
                                
                                // If they match (case-insensitive), don't generate a replacement
                                if matchedText.lowercased() == expectedLower {
                                    continue // Skip - already in correct format, don't replace
                                }
                            }
                            
                            // Additional check: if matched text already equals replacement (case-insensitive), skip
                            if matchedText.lowercased() == replacement.lowercased() {
                                continue
                            }
                            
                            // Skip if already in replacement format
                            if !isAlreadyReplaced(matchedText) {
                                let originalText = String(text[range])
                                // Additional safeguard: don't create replacement if original already matches replacement
                                let originalTrimmed = originalText.trimmed()
                                let replacementTrimmed = replacement.trimmed()
                                
                                // Skip if original text already matches replacement (case-insensitive)
                                if originalTrimmed.lowercased() != replacementTrimmed.lowercased() {
                                    // Create a key to avoid duplicate replacements for the same text
                                    let replacementKey = "\(originalTrimmed.lowercased())->\(replacementTrimmed.lowercased())"
                                    if !seenReplacements.contains(replacementKey) {
                                        replacements.append(TextReplacement(originalText: originalText, replacement: replacement))
                                        processedRanges.append(match.range)
                                        seenReplacements.insert(replacementKey)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // 3. Initials: "OP", "O.P.", "O P"
            if let fi = first.first, let li = last.first {
                let fiLower = String(fi).lowercased()
                let liLower = String(li).lowercased()
                
                // Compact initials: "OP"
                let compactPattern = "\\b\(fiLower)\(liLower)\\b"
                if let regex = try? NSRegularExpression(pattern: compactPattern, options: .caseInsensitive) {
                    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    for match in matches {
                        // Only match if uppercase in original text
                        if let range = Range(match.range, in: text) {
                            let matchedText = String(text[range])
                            if matchedText == matchedText.uppercased() && matchedText.count == 2 {
                                if !processedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                                    // Skip if already in replacement format
                                    if !isAlreadyReplaced(matchedText) {
                                        replacements.append(TextReplacement(originalText: matchedText, replacement: replacement))
                                        processedRanges.append(match.range)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Separated initials: "O.P.", "O P", "O P."
                // FIX: Same fix as above: use (?:\\.|\\b) to ensure we match the trailing period if present
                let separatedPattern = "\\b\(NSRegularExpression.escapedPattern(for: fiLower))\\.?\\s+\(NSRegularExpression.escapedPattern(for: liLower))(?:\\.|\\b)"
                if let regex = try? NSRegularExpression(pattern: separatedPattern, options: .caseInsensitive) {
                    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    for match in matches {
                        if !processedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                            if let range = Range(match.range, in: text) {
                                let matchedText = String(text[range])
                                // Skip if already in replacement format
                                if !isAlreadyReplaced(matchedText) {
                                    replacements.append(TextReplacement(originalText: matchedText, replacement: replacement))
                                    processedRanges.append(match.range)
                                }
                            }
                        }
                    }
                }
            }
            
            // 4. First name only: "Ora" (if unique)
            if firstNameCounts[firstLower] ?? 0 == 1 {
                let firstNamePattern = "\\b\(NSRegularExpression.escapedPattern(for: firstLower))\\b"
                if let regex = try? NSRegularExpression(pattern: firstNamePattern, options: .caseInsensitive) {
                    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    for match in matches {
                        if !processedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                            if let range = Range(match.range, in: text) {
                                let matchedText = String(text[range])
                                // Skip if already in replacement format
                                if !isAlreadyReplaced(matchedText) {
                                    replacements.append(TextReplacement(originalText: matchedText, replacement: replacement))
                                    processedRanges.append(match.range)
                                }
                            }
                        }
                    }
                }
            }
            
            // 5. Nickname: if provided
            if !nick.isEmpty {
                let nickLower = nick.lowercased()
                let nicknamePattern = "\\b\(NSRegularExpression.escapedPattern(for: nickLower))\\b"
                if let regex = try? NSRegularExpression(pattern: nicknamePattern, options: .caseInsensitive) {
                    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    for match in matches {
                        if !processedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                            if let range = Range(match.range, in: text) {
                                let matchedText = String(text[range])
                                // Skip if already in replacement format
                                if !isAlreadyReplaced(matchedText) {
                                    replacements.append(TextReplacement(originalText: matchedText, replacement: replacement))
                                    processedRanges.append(match.range)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Sort by position in text (reverse order to replace from end to start)
        replacements.sort { (r1, r2) in
            if let range1 = text.range(of: r1.originalText, options: .caseInsensitive),
               let range2 = text.range(of: r2.originalText, options: .caseInsensitive) {
                return range1.upperBound > range2.upperBound
            }
            return false
        }
        
        return replacements
    }
    
    // Private Helpers
    private func containsWithBoundary(source: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
    }
    
    private func containsWord(_ text: String, word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    
    private func containsFirstAndLastInitial(_ text: String, first: String, lastInitial: Substring) -> Bool {
        guard !first.isEmpty, let li = lastInitial.first else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: first) + "\\s+" + NSRegularExpression.escapedPattern(for: String(li)) + "\\.?\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    
    private func containsFirstAndLast(_ text: String, first: String, last: String) -> Bool {
        guard !first.isEmpty, !last.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: first) + "\\s+" + NSRegularExpression.escapedPattern(for: last) + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    
    private func containsInitials(_ text: String, firstInitial: Character, lastInitial: Character) -> Bool {
        let fi = String(firstInitial).lowercased()
        let li = String(lastInitial).lowercased()
        // Matches: "a b", "a.b.", "ab" with word boundaries
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: fi) + "\\.?\\s*" + NSRegularExpression.escapedPattern(for: li) + "\\.?\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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
