// ParshaSuggestionService.swift
// Asks the AI router to surface album lessons whose themes connect to a given
// parsha. Caches results in UserDefaults, keyed by parsha and invalidated when
// the album library changes (rename/add/remove).

import Foundation
import CoreData
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
    static let refreshIntervalSeconds: TimeInterval = 3600 // 1 hour rate cap

    private let mcpClient: MCPClientProtocol
    private let context: NSManagedObjectContext
    private let logger = Logger.app(category: "ParshaSuggestionService")

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

    /// Cached suggestions for one parsha, if any.
    func cachedSuggestions(forParshaKey key: String) -> CachedParshaSuggestions? {
        Self.allCachedSuggestions()[key]
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

        // Build a compact, indexed digest. We send numeric indices and let Claude
        // respond with indices to avoid UUID hallucination.
        let digestEntries: [(index: Int, lesson: CDLesson)] = albumLessons.prefix(400)
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

        mcpClient.configureForFeature(.lessonPlanning)
        let response = try await mcpClient.generateStructuredJSON(
            prompt: prompt,
            systemMessage: systemMessage,
            temperature: 0.3,
            maxTokens: 1024,
            model: nil,
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
            throw ParshaSuggestionError.decodeError("Response was not UTF-8")
        }
        let decoded: ResponseShape
        do {
            decoded = try JSONDecoder().decode(ResponseShape.self, from: data)
        } catch {
            logger.error("Failed to decode AI response: \(error.localizedDescription); raw: \(response)")
            throw ParshaSuggestionError.decodeError(error.localizedDescription)
        }

        let indexToLesson = Dictionary(uniqueKeysWithValues: digestEntries.map { ($0.index, $0.lesson) })
        let suggestions: [ParshaSuggestion] = decoded.matches.compactMap { match in
            guard let lesson = indexToLesson[match.index], let id = lesson.id else { return nil }
            return ParshaSuggestion(lessonID: id, reasoning: match.reasoning)
        }

        let cached = CachedParshaSuggestions(
            parshaKey: parshaKey,
            suggestions: suggestions,
            generatedAt: Date(),
            lessonLibraryFingerprint: libraryFingerprint(albumLessons)
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

    private func libraryFingerprint(_ lessons: [CDLesson]) -> String {
        let entries: [String] = lessons.compactMap { lesson in
            guard let id = lesson.id?.uuidString else { return nil }
            return "\(id):\(lesson.name)"
        }.sorted()
        var hasher = Hasher()
        hasher.combine(entries.joined(separator: "|"))
        return String(hasher.finalize())
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
    case decodeError(String)

    var errorDescription: String? {
        switch self {
        case .noAlbumLessons:
            return "No album lessons found. Add lessons from your albums before requesting suggestions."
        case .decodeError(let detail):
            return "Could not parse AI response: \(detail)"
        }
    }
}
