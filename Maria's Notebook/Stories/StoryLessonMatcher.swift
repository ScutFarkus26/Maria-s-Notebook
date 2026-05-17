//
//  StoryLessonMatcher.swift
//  Maria's Notebook
//
//  Finds lessons in the user's library that connect to a given story.
//
//  Pipeline:
//   1. Compute a document vector for the story (title + themes + summary) and for
//      each lesson (name + area + sequence + purpose + writeUp) using Apple's
//      `NLEmbedding.wordEmbedding(for: .english)` — averaged word vectors.
//   2. Rank lessons by cosine similarity, keep the top 25 candidates.
//   3. If an Anthropic API key is configured, ask Claude to rerank the candidates
//      down to 3-5 with a one-sentence pedagogical explanation per match.
//      Otherwise return the top 5 from step 2 with a generic reason.
//
//  Falls back to Jaccard keyword overlap when word embeddings can't be loaded.
//

import Foundation
import CoreData
import NaturalLanguage
import OSLog

@MainActor
enum StoryLessonMatcher {
    private static let logger = Logger.stories

    // MARK: - Public types

    struct LessonMatch: Sendable {
        let lessonID: UUID
        let lessonName: String
        let lessonArea: String
        let reason: String
        /// 0…1 cosine similarity from the embedding pre-filter. Useful for tie-breaking.
        let score: Double
    }

    enum MatcherError: LocalizedError {
        case noLessons
        case noStoryContent
        case claudeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noLessons:
                return "No lessons in your library to match against."
            case .noStoryContent:
                return "This story has too little metadata yet — add themes or a summary first."
            case .claudeFailed(let message):
                return message
            }
        }
    }

    /// Top-level entry point. Returns 0–5 matches.
    static func findConnections(
        for story: CDStory,
        in context: NSManagedObjectContext
    ) async throws -> [LessonMatch] {
        let lessons = fetchAllLessons(in: context)
        guard !lessons.isEmpty else { throw MatcherError.noLessons }

        let storyText = storyEmbeddingText(for: story)
        guard !storyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MatcherError.noStoryContent
        }

        let candidates = preFilterCandidates(storyText: storyText, lessons: lessons, max: 25)
        guard !candidates.isEmpty else { return [] }

        if AnthropicAPIClient.hasAPIKey() {
            do {
                return try await rerankWithClaude(story: story, candidates: candidates)
            } catch {
                logger.warning("Claude rerank failed, falling back to embedding ranking. \(error.localizedDescription, privacy: .public)")
                return fallbackMatches(from: candidates)
            }
        }
        return fallbackMatches(from: candidates)
    }

    // MARK: - Pre-filter

    private struct Candidate {
        let lesson: CDLesson
        let similarity: Double
    }

    private static func preFilterCandidates(
        storyText: String,
        lessons: [CDLesson],
        max maxCount: Int
    ) -> [Candidate] {
        if let embedding = NLEmbedding.wordEmbedding(for: .english),
           let storyVec = documentVector(text: storyText, using: embedding) {
            let scored: [Candidate] = lessons.compactMap { lesson in
                guard lesson.id != nil else { return nil }
                guard let lessonVec = documentVector(
                    text: lessonEmbeddingText(for: lesson),
                    using: embedding
                ) else { return nil }
                let sim = cosine(storyVec, lessonVec)
                guard sim > 0 else { return nil }
                return Candidate(lesson: lesson, similarity: sim)
            }
            return Array(scored.sorted { $0.similarity > $1.similarity }.prefix(maxCount))
        }
        // Embeddings unavailable — Jaccard overlap fallback.
        logger.warning("NLEmbedding unavailable; using Jaccard keyword overlap.")
        return jaccardCandidates(storyText: storyText, lessons: lessons, max: maxCount)
    }

    private static func jaccardCandidates(
        storyText: String,
        lessons: [CDLesson],
        max maxCount: Int
    ) -> [Candidate] {
        let storyTokens = Set(meaningfulTokens(in: storyText))
        guard !storyTokens.isEmpty else { return [] }

        let scored: [Candidate] = lessons.compactMap { lesson in
            guard lesson.id != nil else { return nil }
            let lessonTokens = Set(meaningfulTokens(in: lessonEmbeddingText(for: lesson)))
            let intersection = storyTokens.intersection(lessonTokens)
            guard !intersection.isEmpty else { return nil }
            let union = storyTokens.union(lessonTokens)
            let sim = Double(intersection.count) / Double(union.count)
            return Candidate(lesson: lesson, similarity: sim)
        }
        return Array(scored.sorted { $0.similarity > $1.similarity }.prefix(maxCount))
    }

    // MARK: - Text shaping

    private static func storyEmbeddingText(for story: CDStory) -> String {
        var parts: [String] = []
        let trimmedTitle = story.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { parts.append(trimmedTitle) }
        let themes = story.themesArray.joined(separator: ", ")
        if !themes.isEmpty { parts.append(themes) }
        let trimmedSummary = story.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty { parts.append(trimmedSummary) }
        return parts.joined(separator: ". ")
    }

    private static func lessonEmbeddingText(for lesson: CDLesson) -> String {
        var parts: [String] = []
        if !lesson.name.isEmpty { parts.append(lesson.name) }
        if !lesson.area.isEmpty { parts.append(lesson.area) }
        if !lesson.sequence.isEmpty { parts.append(lesson.sequence) }
        if !lesson.section.isEmpty { parts.append(lesson.section) }
        if !lesson.purpose.isEmpty { parts.append(lesson.purpose) }
        if !lesson.writeUp.isEmpty {
            parts.append(String(lesson.writeUp.prefix(500)))
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Vectorization

    private static func documentVector(text: String, using embedding: NLEmbedding) -> [Double]? {
        let words = meaningfulTokens(in: text)
        guard !words.isEmpty else { return nil }

        var sum = [Double](repeating: 0, count: embedding.dimension)
        var count = 0
        for word in words {
            if let vector = embedding.vector(for: word) {
                for index in 0..<vector.count {
                    sum[index] += vector[index]
                }
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return sum.map { $0 / Double(count) }
    }

    private static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0
        var normL = 0.0
        var normR = 0.0
        for index in 0..<lhs.count {
            dot += lhs[index] * rhs[index]
            normL += lhs[index] * lhs[index]
            normR += rhs[index] * rhs[index]
        }
        guard normL > 0, normR > 0 else { return 0 }
        return dot / (normL.squareRoot() * normR.squareRoot())
    }

    // MARK: - Tokens

    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "of", "in", "on", "at", "to", "for",
        "with", "by", "from", "is", "are", "was", "were", "be", "been", "being",
        "this", "that", "these", "those", "it", "its", "as", "that's", "if", "then",
        "than", "so", "such", "into", "about", "after", "before", "during", "while",
        "their", "there", "they", "them", "his", "her", "hers", "him", "she", "he",
        "we", "us", "our", "you", "your", "yours", "i", "me", "my", "mine"
    ]

    private static func meaningfulTokens(in text: String) -> [String] {
        let lowered = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lowered
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: lowered.startIndex..<lowered.endIndex) { range, _ in
            let token = String(lowered[range])
            if token.count > 2, !stopWords.contains(token) {
                tokens.append(token)
            }
            return true
        }
        return tokens
    }

    // MARK: - Claude rerank

    private struct ClaudeMatch: Decodable {
        let lessonID: String
        let reason: String
    }

    private struct ClaudeResponse: Decodable {
        let matches: [ClaudeMatch]
    }

    private static func rerankWithClaude(
        story: CDStory,
        candidates: [Candidate]
    ) async throws -> [LessonMatch] {
        let candidateLines: String = candidates.compactMap { candidate -> String? in
            guard let id = candidate.lesson.id else { return nil }
            let purpose = candidate.lesson.purpose
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(180)
            let sequence = candidate.lesson.sequence.isEmpty ? "—" : candidate.lesson.sequence
            return "- id: \(id.uuidString); name: \"\(candidate.lesson.name)\"; "
                + "area: \(candidate.lesson.area); sequence: \(sequence); "
                + "purpose: \(purpose)"
        }.joined(separator: "\n")

        let storyContext = """
        Title: \(story.title)
        Themes: \(story.themesArray.joined(separator: ", "))
        Grade band: \(story.gradeBand?.displayName ?? "unknown")
        Summary: \(story.summary)
        """

        let userMessage = """
        STORY:
        \(storyContext)

        CANDIDATE LESSONS (already pre-filtered for relevance):
        \(candidateLines)

        Pick the 3 to 5 candidate lessons that most pedagogically connect with this \
        story for a Montessori classroom. Prefer lessons whose theme, area, or \
        purpose has a meaningful overlap — not just keyword matches. For each chosen \
        lesson write ONE concise sentence explaining the connection (≤ 25 words).

        Return ONLY JSON of the form:
        {"matches":[{"lessonID":"<uuid>","reason":"<one sentence>"}]}
        """

        let system = "You are a Montessori curriculum expert helping a guide find "
            + "connections between children's books and the lessons they teach."

        let client = AnthropicAPIClient()
        let raw: String
        do {
            raw = try await client.generateStructuredJSON(
                prompt: userMessage,
                systemMessage: system,
                temperature: 0.3,
                maxTokens: 1024,
                model: "claude-haiku-4-5",
                timeout: 30
            )
        } catch {
            throw MatcherError.claudeFailed(error.localizedDescription)
        }

        let response: ClaudeResponse
        do {
            response = try JSONDecoder().decode(ClaudeResponse.self, from: Data(raw.utf8))
        } catch {
            logger.warning("Failed to parse Claude rerank response: \(raw, privacy: .public)")
            throw MatcherError.claudeFailed("Couldn't parse Claude's response.")
        }

        let lessonsByID = Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate -> (String, Candidate)? in
            guard let id = candidate.lesson.id?.uuidString else { return nil }
            return (id, candidate)
        })

        var matches: [LessonMatch] = []
        for entry in response.matches {
            guard let candidate = lessonsByID[entry.lessonID],
                  let id = candidate.lesson.id else { continue }
            matches.append(LessonMatch(
                lessonID: id,
                lessonName: candidate.lesson.name,
                lessonArea: candidate.lesson.area,
                reason: entry.reason.trimmingCharacters(in: .whitespacesAndNewlines),
                score: candidate.similarity
            ))
        }
        return matches
    }

    // MARK: - Fallback

    private static func fallbackMatches(from candidates: [Candidate]) -> [LessonMatch] {
        candidates.prefix(5).compactMap { candidate -> LessonMatch? in
            guard let id = candidate.lesson.id else { return nil }
            return LessonMatch(
                lessonID: id,
                lessonName: candidate.lesson.name,
                lessonArea: candidate.lesson.area,
                reason: "Strong overlap on area and theme keywords.",
                score: candidate.similarity
            )
        }
    }

    // MARK: - Fetching

    private static func fetchAllLessons(in context: NSManagedObjectContext) -> [CDLesson] {
        let request: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]
        return context.safeFetch(request)
    }
}
