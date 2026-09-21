//
//  MCPNotebookTools+Lessons.swift
//  Cosmic Daybook
//
//  Naming a lesson from the curriculum: the search tool a model calls
//  before recording a presentation, and the resolver that turns whatever
//  the guide called the lesson into one CDLesson — refusing to guess when
//  the name matches more than one.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Find Lessons

    static func findLessonsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "find_lessons",
            title: "Find Lessons",
            description: "Look up lessons in the guide's curriculum by name, area, or sequence. "
                + "Call this before record_presentation to get the exact lesson, and to check "
                + "which of several similar lessons the guide means. Each result is "
                + "[lesson id=<uuid>] — pass the id or the exact name to record_presentation.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": .string("Part of a lesson name, area, or sequence — "
                            + "e.g. \"racks and tubes\", \"golden beads\", \"geometry\"")
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum lessons to return, 1-25 (default 10)"
                    ]
                ],
                "required": ["query"]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let query = try requireString(arguments, "query")
                let limit = intArgument(arguments, "limit", default: 10, range: 1...25)
                return findLessons(matching: query, limit: limit, in: context())
            }
        )
    }

    private static func findLessons(
        matching query: String, limit: Int, in modelContext: NSManagedObjectContext
    ) -> String {
        let token = query.folded()
        guard !token.isEmpty else { return "A search term is required." }

        let matches = modelContext.safeFetch(CDFetchRequest(CDLesson.self))
            .compactMap { lesson -> (lesson: CDLesson, rank: Int)? in
                guard let rank = matchRank(of: lesson, against: token) else { return nil }
                return (lesson, rank)
            }
            .sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                return $0.lesson.name.localizedCaseInsensitiveCompare($1.lesson.name) == .orderedAscending
            }
            .prefix(limit)

        guard !matches.isEmpty else {
            return "No lessons matched \"\(query)\"."
        }
        return matches.map { "- \(describeLesson($0.lesson))" }.joined(separator: "\n")
    }

    /// Lower ranks sort first: exact name, then a name containing the term,
    /// then its filing. `nil` means the lesson does not match at all.
    private static func matchRank(of lesson: CDLesson, against token: String) -> Int? {
        let name = lesson.name.folded()
        if name == token { return 0 }
        if name.contains(token) { return 1 }
        let filing = "\(lesson.area) \(lesson.sequence) \(lesson.section)".folded()
        if filing.contains(token) { return 2 }
        return nil
    }

    static func describeLesson(_ lesson: CDLesson) -> String {
        let filing = [lesson.area.trimmed(), lesson.sequence.trimmed()]
            .filter { !$0.isEmpty }
            .joined(separator: " › ")
        let id = lesson.id?.uuidString ?? "unknown"
        let key: String = lesson.isKeyLesson ? " (key lesson)" : ""
        return filing.isEmpty
            ? "[lesson id=\(id)] \(lesson.name)\(key)"
            : "[lesson id=\(id)] \(lesson.name) — \(filing)\(key)"
    }

    // MARK: - Lesson Resolution

    /// Resolves a lesson by id, then by exact name, then by a unique partial
    /// name match. Ambiguity is reported with the candidates so the model can
    /// ask the guide which lesson they mean rather than filing the wrong one.
    static func resolveLessonReference(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDLesson {
        let lessons = modelContext.safeFetch(CDFetchRequest(CDLesson.self))

        if let id = UUID(uuidString: reference) {
            guard let lesson = lessons.first(where: { $0.id == id }) else {
                throw MCPToolError("No lesson with id \(reference) was found.")
            }
            return lesson
        }

        let token = reference.folded()
        guard !token.isEmpty else {
            throw MCPToolError("A lesson name or id is required.")
        }

        for candidates in [lessons.filter { $0.name.folded() == token },
                           lessons.filter { $0.name.folded().contains(token) }] {
            if candidates.count == 1, let lesson = candidates.first { return lesson }
            if candidates.count > 1 {
                throw MCPToolError(ambiguityMessage(reference: reference, candidates: candidates))
            }
        }

        throw MCPToolError(
            "No lesson matching \"\(reference)\" is in the curriculum. "
                + "Use find_lessons to search, and ask the guide if nothing fits."
        )
    }

    private static func ambiguityMessage(reference: String, candidates: [CDLesson]) -> String {
        let list = candidates.prefix(8).map { describeLesson($0) }.joined(separator: "\n")
        return "More than one lesson matches \"\(reference)\". Ask which one the guide means:\n\(list)"
    }
}
