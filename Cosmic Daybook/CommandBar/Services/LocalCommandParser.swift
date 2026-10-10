// LocalCommandParser.swift
// Local keyword + fuzzy matching parser for natural language commands

import Foundation

// MARK: - CDLesson Data (lightweight struct for off-main-thread use)

nonisolated struct LessonData: Sendable {
    let id: UUID
    let name: String
    let area: String
    let sequence: String
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

    /// Multi-word intent phrases. Like the single words, the one that comes
    /// first in the sentence decides, so "I gave Maya the cube, she'll keep
    /// working on it" stays a presentation instead of opening New Work.
    private static let phrasePrefixes: [(phrase: String, intent: RecordIntent)] = [
        ("need to", .addTodo),
        ("don't forget", .addTodo),
        ("dont forget", .addTodo),
        ("working on", .assignWork),
        ("follow up", .assignWork)
    ]

    /// Words that may come before the intent word without changing what the
    /// sentence leads with ("I need to…", "Please remind…").
    private static let leadingFillers: Set<String> = [
        "i", "we", "please", "today", "just", "also", "and", "so", "ok", "okay"
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

    /// What the sentence leads with decides. Otherwise the intent word or
    /// phrase that comes first in it does: "I gave Maya the cube, she'll keep
    /// working on it" is a presentation, while "Maya: need to show her the
    /// cube" is a todo, not a lesson that wasn't given.
    private func detectIntent(in text: String) -> (RecordIntent?, Double) {
        let words = Self.words(in: text).map(\.word)

        if let lead = Self.leadingIntent(in: words) {
            return (lead.intent, 0.4)
        }

        for index in words.indices {
            if let intent = Self.intent(startingAt: index, in: words) {
                return (intent, 0.4)
            }
        }

        return (nil, 0.0)
    }

    /// The intent named by the phrase or word at `index`, phrases first.
    private static func intent(startingAt index: Int, in words: [String]) -> RecordIntent? {
        let rest = words[index...]
        for entry in phrasePrefixes where rest.starts(with: entry.phrase.split(separator: " ").map(String.init)) {
            return entry.intent
        }
        return intent(forKeyword: words[index])
    }

    /// The intent the sentence leads with, after any filler words, and how
    /// many words (fillers included) that lead takes up.
    private static func leadingIntent(in words: [String]) -> (intent: RecordIntent, wordCount: Int)? {
        let start = words.firstIndex { !leadingFillers.contains($0) } ?? words.endIndex
        let lead = words[start...]
        for entry in phrasePrefixes {
            let phraseWords = entry.phrase.split(separator: " ").map(String.init)
            if lead.starts(with: phraseWords) {
                return (entry.intent, start + phraseWords.count)
            }
        }
        guard let first = lead.first, let intent = intent(forKeyword: first) else { return nil }
        return (intent, start + 1)
    }

    private static func intent(forKeyword word: String) -> RecordIntent? {
        if presentationKeywords.contains(word) { return .recordPresentation }
        if workKeywords.contains(word) { return .assignWork }
        if practiceKeywords.contains(word) { return .recordPractice }
        if noteKeywords.contains(word) { return .addNote }
        if todoKeywords.contains(word) { return .addTodo }
        return nil
    }

    /// The input's words, lowercased, with their ranges in the input. Curly
    /// apostrophes (the iPhone keyboard's) read as straight ones, so "don’t
    /// forget" matches, and punctuation never sticks to a word ("gave," is "gave").
    private static func words(in text: String) -> [(word: String, range: Range<String.Index>)] {
        text.matches(of: /[\p{L}\p{N}'’]+/).map { match in
            (String(match.output).lowercased().replacingOccurrences(of: "’", with: "'"), match.range)
        }
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

    /// Light-touch extraction: strips the intent word or phrase only where the
    /// sentence leads with it ("Remind me to…", "I noticed…"), together with
    /// any filler words before it. An intent word in the middle of the account
    /// stays, so nothing is cut out of the middle of what the guide wrote.
    private func extractFreeText(from originalInput: String, intent: RecordIntent) -> String {
        let words = Self.words(in: originalInput)
        var result = Substring(originalInput)
        if let lead = Self.leadingIntent(in: words.map(\.word)),
           lead.intent == intent,
           lead.wordCount > 0, lead.wordCount <= words.count {
            result = originalInput[words[lead.wordCount - 1].range.upperBound...]
        }

        // Trim leading/trailing whitespace, colons, dashes, commas
        let trimChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–—,"))
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
            (["social", "together", "collaborat", "friend", "peer", "sequence work"],
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

        return tagKeywords
            .filter { entry in entry.keywords.contains { normalizedText.contains($0) } }
            .map(\.tag)
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
