// LocalCommandParser.swift
// Local keyword + fuzzy matching parser for natural language commands

import Foundation

// MARK: - CDLesson Data (lightweight struct for off-main-thread use)

struct LessonData: Sendable {
    let id: UUID
    let name: String
    let subject: String
    let group: String
}

// MARK: - Local Command Parser

/// Runs heavy parsing off the main thread using the actor pattern (same as StudentTagger).
actor LocalCommandParser {
    private let tagger = StudentTagger()

    // MARK: - Keyword Families

    private static let presentationKeywords: Set<String> = [
        "gave", "give", "presented", "present", "showed", "show",
        "demonstrated", "demonstrate", "introduced", "introduce"
    ]

    private static let workKeywords: Set<String> = [
        "assign", "assigned", "work", "working"
    ]

    private static let practiceKeywords: Set<String> = [
        "practice", "practiced", "practicing"
    ]

    private static let noteKeywords: Set<String> = [
        "note", "noted", "observe", "observed", "noticed",
        "saw", "watching", "seen"
    ]

    private static let todoKeywords: Set<String> = [
        "todo", "remind", "reminder", "task", "remember"
    ]

    /// Multi-word keyword phrases checked before single-word tokenization
    private static let phrasePrefixes: [(phrase: String, intent: RecordIntent)] = [
        ("need to", .addTodo),
        ("don't forget", .addTodo),
        ("dont forget", .addTodo),
        ("working on", .assignWork),
        ("follow up", .assignWork)
    ]

    // MARK: - Public API

    func parse(input: String, students: [StudentData], lessons: [LessonData]) async -> CommandParseResult {
        guard !input.trimmed().isEmpty else {
            return .failed(reason: "Empty input")
        }

        let normalized = input.lowercased().trimmed()

        // Step 1: Detect intent
        let (detectedIntent, intentConfidence) = detectIntent(in: normalized)

        guard let intent = detectedIntent else {
            return .failed(reason: "Could not determine what you want to do. "
                + "Try starting with 'gave', 'assign', 'note', or 'remind'.")
        }

        // Step 2: Extract student names using the existing StudentTagger
        let studentResult = await tagger.findStudentMatches(in: input, studentData: students)
        let matchedStudentIDs = Array(studentResult.exact.union(studentResult.autoSelect))

        // Step 3: Extract lesson name via fuzzy matching
        let (matchedLessonID, matchedLessonName) = findBestLessonMatch(
            in: normalized, lessons: lessons, students: students
        )

        // Step 4: Extract free text — only strip the intent keyword prefix,
        // preserving the user's original observation text intact
        let freeText = extractFreeText(from: input, intent: intent)

        // Step 5: Infer Montessori observation tags from the text
        let inferredTags = inferTags(from: normalized)

        // Step 6: Compute confidence
        var confidence = intentConfidence
        if !matchedStudentIDs.isEmpty { confidence += 0.2 }
        if matchedLessonID != nil { confidence += 0.2 }
        // Bonus for well-formed short input
        if normalized.split(separator: " ").count <= 12 { confidence += 0.1 }
        confidence = min(confidence, 1.0)

        let command = ParsedCommand(
            intent: intent,
            studentIDs: matchedStudentIDs,
            lessonID: matchedLessonID,
            rawStudentNames: matchedStudentIDs.compactMap { id in
                students.first { $0.id == id }.map { "\($0.firstName) \($0.lastName)" }
            },
            rawLessonName: matchedLessonName,
            freeText: freeText,
            inferredTags: inferredTags,
            confidence: confidence
        )

        if confidence >= ParsedCommand.confidenceThreshold {
            return .parsed(command)
        } else {
            return .ambiguous(suggestions: [command])
        }
    }

    // MARK: - Intent Detection

    private func detectIntent(in text: String) -> (RecordIntent?, Double) {
        // Check multi-word phrases first
        for entry in Self.phrasePrefixes where text.contains(entry.phrase) {
            return (entry.intent, 0.4)
        }

        // Tokenize and check single keywords
        let words = Set(text.split(separator: " ").map { String($0) })

        if !words.isDisjoint(with: Self.presentationKeywords) {
            return (.recordPresentation, 0.4)
        }
        if !words.isDisjoint(with: Self.workKeywords) {
            return (.assignWork, 0.4)
        }
        if !words.isDisjoint(with: Self.practiceKeywords) {
            return (.recordPractice, 0.4)
        }
        if !words.isDisjoint(with: Self.noteKeywords) {
            return (.addNote, 0.4)
        }
        if !words.isDisjoint(with: Self.todoKeywords) {
            return (.addTodo, 0.4)
        }

        return (nil, 0.0)
    }

    // MARK: - CDLesson Matching

    private struct LessonMatchCandidate {
        let id: UUID
        let name: String
        let score: Int
    }

    private func findBestLessonMatch(
        in text: String,
        lessons: [LessonData],
        students: [StudentData]
    ) -> (UUID?, String?) {
        guard !lessons.isEmpty else { return (nil, nil) }

        var bestMatch: LessonMatchCandidate?

        for lesson in lessons {
            let lessonNameLower = lesson.name.lowercased()

            // Exact substring match (best)
            if text.localizedCaseInsensitiveContains(lesson.name) {
                let score = lesson.name.count * 3 // prefer longer exact matches
                if bestMatch.map({ score > $0.score }) ?? true {
                    bestMatch = LessonMatchCandidate(id: lesson.id, name: lesson.name, score: score)
                }
                continue
            }

            // N-gram matching: build sliding windows of the input text
            let words = text.split(separator: " ").map { String($0) }
            let lessonWords = lessonNameLower.split(separator: " ").map { String($0) }
            let ngramSize = lessonWords.count

            guard ngramSize > 0, ngramSize <= words.count else { continue }

            for start in 0...(words.count - ngramSize) {
                let ngram = words[start..<(start + ngramSize)].joined(separator: " ")
                let distance = levenshteinDistance(ngram, lessonNameLower)
                let maxLen = max(ngram.count, lessonNameLower.count)

                // Accept if edit distance is less than 30% of name length
                if maxLen > 0 && Double(distance) / Double(maxLen) < 0.3 {
                    let score = lessonNameLower.count * 2
                    if bestMatch.map({ score > $0.score }) ?? true {
                        bestMatch = LessonMatchCandidate(id: lesson.id, name: lesson.name, score: score)
                    }
                }
            }
        }

        if let match = bestMatch {
            return (match.id, match.name)
        }
        return (nil, nil)
    }

    // MARK: - Free Text Extraction

    /// Light-touch extraction: only strips the intent trigger keyword/phrase from the
    /// original input, preserving student names, filler words, and everything else.
    private func extractFreeText(from originalInput: String, intent: RecordIntent) -> String {
        let keywords: Set<String> = switch intent {
        case .recordPresentation: Self.presentationKeywords
        case .assignWork: Self.workKeywords
        case .recordPractice: Self.practiceKeywords
        case .addNote: Self.noteKeywords
        case .addTodo: Self.todoKeywords
        }

        var result = originalInput

        // Check multi-word phrases first
        for entry in Self.phrasePrefixes where entry.intent == intent {
            if let range = result.range(of: entry.phrase, options: .caseInsensitive) {
                result.removeSubrange(range)
                break
            }
        }

        // Remove the first occurrence of the matched intent keyword
        let lower = result.lowercased()
        for keyword in keywords {
            if let range = lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b",
                                       options: .regularExpression) {
                // Map the range from the lowercased copy to the original
                let startOffset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                let endOffset = lower.distance(from: lower.startIndex, to: range.upperBound)
                let originalStart = result.index(result.startIndex, offsetBy: startOffset)
                let originalEnd = result.index(result.startIndex, offsetBy: endOffset)
                result.removeSubrange(originalStart..<originalEnd)
                break
            }
        }

        // Trim leading/trailing whitespace, colons, dashes
        let trimChars = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":-–—"))
        return result.trimmingCharacters(in: trimChars)
    }

    // MARK: - Tag Inference

    /// Infer Montessori observation tags from text via keyword matching.
    private func inferTags(from normalizedText: String) -> [String] {
        let tagKeywords: [(keywords: [String], tag: String)] = [
            (["concentrat", "focused", "deep work", "absorbed", "engrossed"],
             MontessoriObservationTags.concentration),
            (["repeat", "again and again", "over and over"],
             MontessoriObservationTags.repetition),
            (["social", "together", "collaborat", "friend", "peer", "group work"],
             MontessoriObservationTags.socialInteraction),
            (["independent", "by himself", "by herself", "on her own", "on his own", "alone"],
             MontessoriObservationTags.independence),
            (["material", "manipulat", "using the"],
             MontessoriObservationTags.materialUse),
            (["walking", "running", "climbing", "gross motor", "fine motor"],
             MontessoriObservationTags.movement),
            (["order", "organiz", "tidy", "neat", "arranging"],
             MontessoriObservationTags.loveOfOrder),
            (["disciplin", "self-control", "patient", "waiting"],
             MontessoriObservationTags.selfDiscipline),
            (["grace", "courtesy", "polite", "manners"],
             MontessoriObservationTags.graceAndCourtesy),
            (["practical life", "pouring", "sweeping", "buttoning", "dressing"],
             MontessoriObservationTags.practicalLife),
            (["sensorial", "texture", "color sorting", "grading"],
             MontessoriObservationTags.sensorial),
            (["language", "reading", "writing", "phonetic", "letter sound"],
             MontessoriObservationTags.languageDevelopment),
            (["math", "counting", "number", "addition", "stamp game", "bead"],
             MontessoriObservationTags.mathematicalThinking),
            (["culture", "geography", "continent", "map", "science", "botany", "zoology"],
             MontessoriObservationTags.culturalExploration)
        ]

        var matched: [String] = []
        for entry in tagKeywords {
            if entry.keywords.contains(where: { normalizedText.contains($0) }) {
                matched.append(entry.tag)
            }
        }
        return matched
    }

    // MARK: - Levenshtein Distance

    private func levenshteinDistance(_ source: String, _ target: String) -> Int {
        let sourceArr = Array(source)
        let targetArr = Array(target)
        let sourceLen = sourceArr.count
        let targetLen = targetArr.count

        if sourceLen == 0 { return targetLen }
        if targetLen == 0 { return sourceLen }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: targetLen + 1), count: sourceLen + 1)

        for idx in 0...sourceLen { matrix[idx][0] = idx }
        for idx in 0...targetLen { matrix[0][idx] = idx }

        for sIdx in 1...sourceLen {
            for tIdx in 1...targetLen {
                let cost = sourceArr[sIdx - 1] == targetArr[tIdx - 1] ? 0 : 1
                matrix[sIdx][tIdx] = min(
                    matrix[sIdx - 1][tIdx] + 1,      // deletion
                    matrix[sIdx][tIdx - 1] + 1,      // insertion
                    matrix[sIdx - 1][tIdx - 1] + cost // substitution
                )
            }
        }

        return matrix[sourceLen][targetLen]
    }
}
