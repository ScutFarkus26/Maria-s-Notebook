// ParshaSuggestionService.swift
// Asks the AI router to surface album lessons whose themes connect to a given
// parsha. Caches results in UserDefaults, keyed by parsha and invalidated when
// the album library changes (rename/add/remove).

import Foundation
import CoreData
import CryptoKit
import os.log

struct ParshaSuggestion: Codable, Sendable, Identifiable {
    let lessonID: UUID
    let reasoning: String
    var id: UUID { lessonID }
}

struct CachedParshaSuggestions: Codable, Sendable {
    let parshaKey: String
    let suggestions: [ParshaSuggestion]
    let generatedAt: Date
    let lessonLibraryFingerprint: String
}

final class ParshaSuggestionService {

    static let cacheStorageKey = "ParshaSuggestionCache.v1"

    private let mcpClient: MCPClientProtocol
    private let context: NSManagedObjectContext
    private let logger = Logger.parshaSuggestionService

    init(mcpClient: MCPClientProtocol, context: NSManagedObjectContext) {
        self.mcpClient = mcpClient
        self.context = context
    }

    /// All cached suggestions across all parshas (decoded on read).
    static func allCachedSuggestions() -> [String: CachedParshaSuggestions] {
        guard let data = UserDefaults.standard.data(forKey: cacheStorageKey),
              let decoded = try? JSONDecoder().decode([String: CachedParshaSuggestions].self, from: data) else {
            return [:]
        }
        return decoded
    }

    /// Cached suggestions for one parsha, if any, while the album library is
    /// still the one they were found in. After a lesson is added, renamed or
    /// removed they are stale, and the parsha offers to look again.
    func cachedSuggestions(forParshaKey key: String) -> CachedParshaSuggestions? {
        guard let cached = Self.allCachedSuggestions()[key] else { return nil }
        let current = Self.libraryFingerprint(fetchAlbumLessons())
        return cached.lessonLibraryFingerprint == current ? cached : nil
    }

    /// Generates fresh AI suggestions for the parsha. Throws on network/parse error.
    func generateSuggestions(forParshaKey parshaKey: String) async throws -> CachedParshaSuggestions {
        let albumLessons = fetchAlbumLessons()
        guard !albumLessons.isEmpty else {
            throw ParshaSuggestionError.noAlbumLessons
        }

        let metadata = ParshaMetadataService.metadata(forKey: parshaKey)
        let parshaName = HebrewParshaService.displayName(forKey: parshaKey)
        let topics = metadata?.topics ?? []
        let passageRange = metadata?.passageRange ?? ""

        // Build a compact, indexed digest. We send numeric indices and let the model
        // respond with indices to avoid UUID hallucination. A large library is cut
        // to the lessons whose words come closest to the parsha's, not to the
        // first ones by name.
        let shortlist = Self.shortlist(
            albumLessons,
            matching: [parshaName, passageRange] + topics,
            limit: Self.digestLimit
        )
        let digestEntries: [(index: Int, lesson: CDLesson)] = shortlist
            .enumerated()
            .map { ($0.offset + 1, $0.element) }
        let digestText = digestEntries.map { entry in
            let lesson = entry.lesson
            let purpose = String(lesson.purpose.trimmed().prefix(120))
            let writeUp = String(lesson.writeUp.trimmed().prefix(180))
            let parts = [purpose, writeUp].filter { !$0.isEmpty }.joined(separator: " ")
            let area = lesson.area
            let sequence = lesson.sequence
            return "\(entry.index). \(lesson.name) [\(area)\(sequence.isEmpty ? "" : " / \(sequence)")] — \(parts)"
        }.joined(separator: "\n")

        let prompt = """
        Parsha: \(parshaName)
        Passages: \(passageRange)
        Topics:
        \(topics.map { "- \($0)" }.joined(separator: "\n"))

        Available album lessons (indexed):
        \(digestText)

        Select up to 5 lessons whose themes genuinely connect to this parsha — look beyond
        surface area overlap to find connections in character, moral, or thematic resonance.
        If fewer than 5 connect meaningfully, return fewer.

        Respond with strict JSON:
        {"matches": [{"index": <integer>, "reasoning": "<1-2 sentence connection>"}]}
        """

        let systemMessage = """
        You are a Montessori curriculum advisor with deep knowledge of Torah commentary. \
        You help teachers see thematic connections between their existing classroom \
        lessons and weekly parshas. Be precise and avoid stretched analogies.
        """

        let response = try await mcpClient.generateStructuredJSON(
            prompt: prompt,
            systemMessage: systemMessage,
            temperature: 0.3,
            maxTokens: 1024,
            timeout: 90
        )

        struct ResponseShape: Decodable {
            struct Match: Decodable {
                let index: Int
                let reasoning: String
            }
            let matches: [Match]
        }
        guard let data = response.data(using: .utf8) else {
            logger.error("AI response was not UTF-8")
            throw LocalModelError.invalidJSON
        }
        let decoded: ResponseShape
        do {
            decoded = try JSONDecoder().decode(ResponseShape.self, from: data)
        } catch {
            logger.error("Failed to decode AI response: \(error.localizedDescription); raw: \(response)")
            throw LocalModelError.invalidJSON
        }

        let indexToLesson = Dictionary(
            digestEntries.map { ($0.index, $0.lesson) }, uniquingKeysWith: { first, _ in first }
        )
        let suggestions: [ParshaSuggestion] = decoded.matches.compactMap { match in
            guard let lesson = indexToLesson[match.index], let id = lesson.id else { return nil }
            return ParshaSuggestion(lessonID: id, reasoning: match.reasoning)
        }

        let cached = CachedParshaSuggestions(
            parshaKey: parshaKey,
            suggestions: suggestions,
            generatedAt: Date(),
            lessonLibraryFingerprint: Self.libraryFingerprint(albumLessons)
        )
        Self.persist(cached)
        return cached
    }

    // MARK: - Internals

    private func fetchAlbumLessons() -> [CDLesson] {
        let req = CDFetchRequest(CDLesson.self)
        req.predicate = NSPredicate(format: "sourceRaw == %@", LessonSource.album.rawValue)
        req.sortDescriptors = [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]
        return context.safeFetch(req)
    }

    /// How many album lessons one request describes to the model.
    static let digestLimit = 400

    /// A digest of the album library's lesson ids and names, the same on every
    /// launch (`Hasher` is seeded per process, so its value never matched again).
    static func libraryFingerprint(_ lessons: [CDLesson]) -> String {
        let entries: [String] = Set(lessons.compactMap { lesson -> String? in
            guard let id = lesson.id?.uuidString else { return nil }
            return "\(id):\(lesson.name)"
        }).sorted()
        let digest = SHA256.hash(data: Data(entries.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The `limit` lessons sharing the most words with `texts` (the parsha's
    /// name, passages and topics), ties kept in the order given. Words shorter
    /// than four letters don't count. A library within the limit is kept whole.
    static func shortlist(_ lessons: [CDLesson], matching texts: [String], limit: Int) -> [CDLesson] {
        let unique = lessons.uniqueByID
        guard unique.count > limit else { return unique }
        let wanted = Set(texts.flatMap(words(in:)))
        let scores: [Int] = unique.map { lesson in
            let text = [lesson.name, lesson.area, lesson.sequence, lesson.purpose, lesson.writeUp]
                .joined(separator: " ")
            return Set(words(in: text)).intersection(wanted).count
        }
        return unique.indices
            .sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
            .prefix(limit)
            .map { unique[$0] }
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 4 }
    }

    private static func persist(_ payload: CachedParshaSuggestions) {
        var all = allCachedSuggestions()
        all[payload.parshaKey] = payload
        if let encoded = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(encoded, forKey: cacheStorageKey)
        }
    }
}

enum ParshaSuggestionError: LocalizedError {
    case noAlbumLessons

    var errorDescription: String? {
        switch self {
        case .noAlbumLessons:
            return "There are no album lessons yet. Add lessons from your albums, then try again."
        }
    }
}
