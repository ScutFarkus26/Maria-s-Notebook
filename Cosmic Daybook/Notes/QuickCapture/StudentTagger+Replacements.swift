import Foundation

// MARK: - Replacement Generation

extension StudentTagger {

    // MARK: - Text Formatting (Deterministic)

    /// Format Names: every full name, "First L" and unshared first name becomes the
    /// child's short name ("Maya Smith" → "Maya S"). One pass over the text she
    /// typed, so a name already in short form is left alone. A first name two
    /// children share and a nickname ("a sunny day") are never rewritten.
    func formatStudentNames(in text: String, studentData: [StudentData]) -> String {
        guard !text.isEmpty else { return text }

        struct Candidate {
            let range: Range<String.Index>
            let replacement: String
        }

        let foldedText = FoldedText(text)
        var firstNameCounts: [String: Int] = [:]
        for student in studentData {
            firstNameCounts[student.firstName.folded(), default: 0] += 1
        }

        var candidates: [Candidate] = []
        for student in studentData {
            let replacement = StudentFormatter.displayName(
                firstName: student.firstName, lastName: student.lastName
            )
            var ranges = PatternMatchHelpers.fullNameRanges(
                first: student.firstName, last: student.lastName, in: foldedText
            )
            ranges += PatternMatchHelpers.firstAndInitialRanges(
                first: student.firstName, last: student.lastName, in: foldedText
            )
            if firstNameCounts[student.firstName.folded()] == 1 {
                ranges += PatternMatchHelpers.wordRanges(of: student.firstName, in: foldedText)
            }
            candidates += ranges.map { Candidate(range: $0, replacement: replacement) }
        }

        // Leftmost first, and the longest name where two start together
        // ("Maya Smith" over "Maya"), skipping anything inside a name already taken.
        candidates.sort {
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            return $0.range.upperBound > $1.range.upperBound
        }
        var resultText = ""
        var cursor = text.startIndex
        for candidate in candidates where candidate.range.lowerBound >= cursor {
            resultText += text[cursor..<candidate.range.lowerBound]
            resultText += candidate.replacement
            cursor = candidate.range.upperBound
        }
        resultText += text[cursor...]
        return resultText
    }

    // MARK: - Replacement Generation

    /// Quick Note's tidy-as-you-type: clear initials of a tagged child become the
    /// child's short name ("JD" → "Jonah D"). Nothing else is rewritten: a
    /// replacement never drops what she typed, so full names, "First L", first
    /// names and nicknames stay as written. One replacement per place found, each
    /// carrying its range; ordered from the end of the text.
    func generateReplacements(
        for exactMatches: Set<UUID>,
        in text: FoldedText,
        studentData: [StudentData]
    ) -> [TextReplacement] {
        var studentsByInitials: [String: [StudentData]] = [:]
        for student in studentData {
            guard let key = PatternMatchHelpers.initialsKey(
                first: student.firstName, last: student.lastName
            ) else { continue }
            studentsByInitials[key, default: []].append(student)
        }

        let firstNames = Set(studentData.map { $0.firstName.folded() })
        var replacements: [TextReplacement] = []

        for match in PatternMatchHelpers.initialsMatches(in: text, firstNames: firstNames).reversed() {
            guard let candidates = studentsByInitials[match.key], candidates.count == 1,
                  let student = candidates.first, exactMatches.contains(student.id) else { continue }
            let original = String(text.original[match.range])
            let replacement = StudentFormatter.displayName(
                firstName: student.firstName, lastName: student.lastName
            )
            guard original != replacement else { continue }
            replacements.append(TextReplacement(
                originalText: original, replacement: replacement, range: NSRange(match.range, in: text.original)
            ))
        }

        return replacements
    }
}
