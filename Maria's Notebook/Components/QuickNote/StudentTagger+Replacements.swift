import Foundation

// MARK: - Replacement Generation

extension StudentTagger {

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

            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let range = NSRange(resultText.startIndex..<resultText.endIndex, in: resultText)
                resultText = regex.stringByReplacingMatches(in: resultText, options: [], range: range, withTemplate: searchTerm.replacement)
            } catch {
                print("\u{26a0}\u{fe0f} [\(#function)] Failed to create regex for term '\(searchTerm.term)': \(error)")
            }
        }

        return resultText
    }

    // MARK: - Replacement Generation

    func generateReplacements(
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
                    do {
                        let regex = try NSRegularExpression(pattern: "^\(expectedPattern)$", options: .caseInsensitive)
                        let range = NSRange(matchedText.startIndex..., in: matchedText)
                        if regex.firstMatch(in: matchedText, options: [], range: range) != nil {
                            return true
                        }
                    } catch {
                        print("\u{26a0}\u{fe0f} [\(#function)] Failed to create regex for pattern '\(expectedPattern)': \(error)")
                    }
                }

                return false
            }

            // 1. Full name: "Ora Pardo"
            let fullNamePattern = "\\b\(NSRegularExpression.escapedPattern(for: firstLower))\\s+\(NSRegularExpression.escapedPattern(for: lastLower))\\b"
            do {
                let regex = try NSRegularExpression(pattern: fullNamePattern, options: .caseInsensitive)
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
            } catch {
                print("\u{26a0}\u{fe0f} [\(#function)] Failed to create regex for full name pattern: \(error)")
            }

            // 2. First + Last Initial: "Ora P" or "Ora P."
            // Only match if we need to replace it (don't match if already in replacement format)
            // If replacement format is "FirstName LastInitial.", don't match text that already ends with period
            // FIX: Use (?:\\.|\\b) instead of \\.?\\b to ensure we consume the period if present,
            // preventing partial matches on "Sarah M." (which would otherwise match "Sarah M" and cause double periods)
            let firstLastInitialPattern = "\\b\(NSRegularExpression.escapedPattern(for: firstLower))\\s+\(NSRegularExpression.escapedPattern(for: firstInitial))(?:\\.|\\b)"
            do {
                let regex = try NSRegularExpression(pattern: firstLastInitialPattern, options: .caseInsensitive)
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
            } catch {
                print("\u{26a0}\u{fe0f} [\(#function)] Failed to create regex for first+last initial pattern: \(error)")
            }

            // 3. Initials: "OP", "O.P.", "O P"
            if let fi = first.first, let li = last.first {
                let fiLower = String(fi).lowercased()
                let liLower = String(li).lowercased()

                // Compact initials: "OP"
                let compactPattern = "\\b\(fiLower)\(liLower)\\b"
                do {
                    let regex = try NSRegularExpression(pattern: compactPattern, options: .caseInsensitive)
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
                } catch {
                    print("\u{26a0}\u{fe0f} [\(#function)] Failed to create regex for compact initials: \(error)")
                }

                // Separated initials: "O.P.", "O P", "O P."
                // FIX: Same fix as above: use (?:\\.|\\b) to ensure we match the trailing period if present
                let separatedPattern = "\\b\(NSRegularExpression.escapedPattern(for: fiLower))\\.?\\s+\(NSRegularExpression.escapedPattern(for: liLower))(?:\\.|\\b)"
                do {
                    let regex = try NSRegularExpression(pattern: separatedPattern, options: .caseInsensitive)
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
                } catch {
                    print("\u{26a0}\u{fe0f} [\(#function)] Failed to create regex for separated initials: \(error)")
                }
            }

            // 4. First name only: "Ora" (if unique)
            if firstNameCounts[firstLower] ?? 0 == 1 {
                let firstNamePattern = "\\b\(NSRegularExpression.escapedPattern(for: firstLower))\\b"
                do {
                    let regex = try NSRegularExpression(pattern: firstNamePattern, options: .caseInsensitive)
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
                } catch {
                    print("\u{26a0}\u{fe0f} [\(#function)] Failed to create regex for first name pattern: \(error)")
                }
            }

            // 5. Nickname: if provided
            if !nick.isEmpty {
                let nickLower = nick.lowercased()
                let nicknamePattern = "\\b\(NSRegularExpression.escapedPattern(for: nickLower))\\b"
                do {
                    let regex = try NSRegularExpression(pattern: nicknamePattern, options: .caseInsensitive)
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
                } catch {
                    print("\u{26a0}\u{fe0f} [\(#function)] Failed to create regex for nickname pattern: \(error)")
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
}
