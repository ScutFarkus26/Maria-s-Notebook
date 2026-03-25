import Foundation
import OSLog

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
                resultText = regex.stringByReplacingMatches(
                    in: resultText, options: [], range: range,
                    withTemplate: searchTerm.replacement
                )
            } catch {
                Logger.notes.error("[\(#function)] Failed to create regex for term '\(searchTerm.term)': \(error)")
            }
        }

        return resultText
    }

    // MARK: - Per-Student Replacement Context

    /// Bundles per-student data needed by all replacement pattern helpers.
    private struct ReplacementContext {
        let first: String
        let last: String
        let firstLower: String
        let lastLower: String
        let firstInitial: String
        let nick: String
        let replacement: String

        init(student: StudentData, firstNameCounts: [String: Int]) {
            first = student.firstName
            last = student.lastName
            firstLower = first.lowercased()
            lastLower = last.lowercased()
            firstInitial = last.prefix(1).lowercased()
            nick = (student.nickname ?? "").trimmed()

            if firstNameCounts[firstLower] ?? 0 > 1 {
                replacement = "\(first) \(firstInitial.uppercased())."
            } else {
                replacement = first
            }
        }
    }

    // MARK: - Replacement Generation

    func generateReplacements(
        for exactMatches: Set<UUID>,
        in text: String,
        studentData: [StudentData],
        firstNameCounts: [String: Int]
    ) -> [TextReplacement] {
        var replacements: [TextReplacement] = []
        var seenReplacements: Set<String> = []

        for studentID in exactMatches {
            guard let student = studentData.first(where: { $0.id == studentID }) else { continue }

            let ctx = ReplacementContext(student: student, firstNameCounts: firstNameCounts)
            var processedRanges: [NSRange] = []

            // 1. Full name (most specific)
            collectFullNameReplacements(
                in: text, ctx: ctx, replacements: &replacements, processedRanges: &processedRanges
            )
            // 2. First + Last Initial ("Ora P" / "Ora P.")
            collectFirstLastInitialReplacements(
                in: text, ctx: ctx, replacements: &replacements,
                processedRanges: &processedRanges, seenReplacements: &seenReplacements
            )
            // 3. Initials ("OP", "O.P.", "O P")
            collectInitialsReplacements(
                in: text, ctx: ctx, replacements: &replacements, processedRanges: &processedRanges
            )
            // 4. First name only (if unique)
            if firstNameCounts[ctx.firstLower] ?? 0 == 1 {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: ctx.firstLower))\\b"
                collectSimplePatternMatches(
                    pattern: pattern, in: text, ctx: ctx,
                    replacements: &replacements, processedRanges: &processedRanges
                )
            }
            // 5. Nickname
            if !ctx.nick.isEmpty {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: ctx.nick.lowercased()))\\b"
                collectSimplePatternMatches(
                    pattern: pattern, in: text, ctx: ctx,
                    replacements: &replacements, processedRanges: &processedRanges
                )
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

    // MARK: - Replacement Helpers

    /// Checks whether matched text is already in the target replacement format.
    private func isAlreadyInReplacementFormat(_ matchedText: String, ctx: ReplacementContext) -> Bool {
        let matchedTrimmed = matchedText.trimmed()
        let replacementTrimmed = ctx.replacement.trimmed()

        if matchedTrimmed.lowercased() == replacementTrimmed.lowercased() { return true }

        if replacementTrimmed.hasSuffix(".") {
            let expectedPattern = "\(ctx.firstLower) \(ctx.firstInitial)\\."
            do {
                let regex = try NSRegularExpression(
                    pattern: "^\(expectedPattern)$", options: .caseInsensitive
                )
                let range = NSRange(matchedText.startIndex..., in: matchedText)
                if regex.firstMatch(in: matchedText, options: [], range: range) != nil {
                    return true
                }
            } catch {
                Logger.notes.error("[\(#function)] Failed to create regex for '\(expectedPattern)': \(error)")
            }
        }

        return false
    }

    /// Shared helper: finds case-insensitive regex matches and appends non-overlapping replacements.
    private func collectSimplePatternMatches(
        pattern: String, in text: String, ctx: ReplacementContext,
        replacements: inout [TextReplacement], processedRanges: inout [NSRange]
    ) {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches where !processedRanges.contains(where: {
                NSIntersectionRange($0, match.range).length > 0
            }) {
                if let range = Range(match.range, in: text) {
                    let matchedText = String(text[range])
                    if !isAlreadyInReplacementFormat(matchedText, ctx: ctx) {
                        replacements.append(
                            TextReplacement(originalText: matchedText, replacement: ctx.replacement)
                        )
                        processedRanges.append(match.range)
                    }
                }
            }
        } catch {
            Logger.notes.error("[\(#function)] Failed to create regex for pattern: \(error)")
        }
    }

    /// Pattern 1: Full name matches ("Ora Pardo").
    private func collectFullNameReplacements(
        in text: String, ctx: ReplacementContext,
        replacements: inout [TextReplacement], processedRanges: inout [NSRange]
    ) {
        let escapedFirst = NSRegularExpression.escapedPattern(for: ctx.firstLower)
        let escapedLast = NSRegularExpression.escapedPattern(for: ctx.lastLower)
        let pattern = "\\b\(escapedFirst)\\s+\(escapedLast)\\b"
        collectSimplePatternMatches(
            pattern: pattern, in: text, ctx: ctx,
            replacements: &replacements, processedRanges: &processedRanges
        )
    }

    /// Pattern 2: First + Last Initial matches ("Ora P" / "Ora P.") with dedup.
    private func collectFirstLastInitialReplacements(
        in text: String, ctx: ReplacementContext,
        replacements: inout [TextReplacement], processedRanges: inout [NSRange],
        seenReplacements: inout Set<String>
    ) {
        let escapedFirst = NSRegularExpression.escapedPattern(for: ctx.firstLower)
        let escapedInit = NSRegularExpression.escapedPattern(for: ctx.firstInitial)
        let pattern = "\\b\(escapedFirst)\\s+\(escapedInit)(?:\\.|\\b)"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches where !processedRanges.contains(where: {
                NSIntersectionRange($0, match.range).length > 0
            }) {
                guard let range = Range(match.range, in: text) else { continue }
                let matchedText = String(text[range]).trimmed()

                // Skip if already in correct format
                if isAlreadyInReplacementFormat(matchedText, ctx: ctx) { continue }
                if matchedText.lowercased() == ctx.replacement.lowercased() { continue }

                // Check period-ending format match
                if ctx.replacement.hasSuffix(".") && matchedText.hasSuffix(".") {
                    let expected = "\(ctx.first) \(ctx.firstInitial.uppercased())."
                    if matchedText.lowercased() == expected.lowercased() { continue }
                }

                let originalText = String(text[range])
                let origLower = originalText.trimmed().lowercased()
                let replLower = ctx.replacement.trimmed().lowercased()
                guard origLower != replLower else { continue }

                let replacementKey = "\(origLower)->\(replLower)"
                guard !seenReplacements.contains(replacementKey) else { continue }

                replacements.append(
                    TextReplacement(originalText: originalText, replacement: ctx.replacement)
                )
                processedRanges.append(match.range)
                seenReplacements.insert(replacementKey)
            }
        } catch {
            Logger.notes.error("[\(#function)] Failed to create regex for first+last initial: \(error)")
        }
    }

    /// Pattern 3: Compact ("OP") and separated ("O.P.", "O P") initials.
    private func collectInitialsReplacements(
        in text: String, ctx: ReplacementContext,
        replacements: inout [TextReplacement], processedRanges: inout [NSRange]
    ) {
        guard let fi = ctx.first.first, let li = ctx.last.first else { return }
        let fiLower = String(fi).lowercased()
        let liLower = String(li).lowercased()

        // Compact initials: "OP" (uppercase only)
        let compactPattern = "\\b\(fiLower)\(liLower)\\b"
        do {
            let regex = try NSRegularExpression(pattern: compactPattern, options: .caseInsensitive)
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                let matchedText = String(text[range])
                guard matchedText == matchedText.uppercased() && matchedText.count == 2 else { continue }
                guard !processedRanges.contains(where: {
                    NSIntersectionRange($0, match.range).length > 0
                }) else { continue }
                if !isAlreadyInReplacementFormat(matchedText, ctx: ctx) {
                    replacements.append(
                        TextReplacement(originalText: matchedText, replacement: ctx.replacement)
                    )
                    processedRanges.append(match.range)
                }
            }
        } catch {
            Logger.notes.error("[\(#function)] Failed to create regex for compact initials: \(error)")
        }

        // Separated initials: "O.P.", "O P", "O P."
        let escFi = NSRegularExpression.escapedPattern(for: fiLower)
        let escLi = NSRegularExpression.escapedPattern(for: liLower)
        let separatedPattern = "\\b\(escFi)\\.?\\s+\(escLi)(?:\\.|\\b)"
        collectSimplePatternMatches(
            pattern: separatedPattern, in: text, ctx: ctx,
            replacements: &replacements, processedRanges: &processedRanges
        )
    }
}
