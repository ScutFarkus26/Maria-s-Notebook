import Foundation
import CoreData
import OSLog

/// Entity types that can be indexed for full-text search.
enum SearchableEntityType: String, CaseIterable, Sendable {
    case note, lesson, student, todo, work
}

/// A lightweight search result reference.
struct SearchResult: Hashable, Identifiable, Sendable {
    let id: UUID
    let entityType: SearchableEntityType
    let title: String
    let snippet: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(entityType)
    }
}

/// In-memory inverted index for full-text search across all searchable entities.
/// Built on app launch and updated incrementally on entity create/update/delete.
@Observable
@MainActor
final class SearchIndexService {
    static let shared = SearchIndexService()
    nonisolated private static let logger = Logger.app(category: "SearchIndex")

    /// Token -> set of matching results
    private var index: [String: Set<SearchResult>] = [:]

    /// All indexed results by ID for quick removal
    private var resultsById: [UUID: SearchResult] = [:]

    private(set) var isReady = false

    private init() {}

    // MARK: - Core Data Index Building

    func rebuildIndex(context: NSManagedObjectContext) {
        let start = Date()

        index.removeAll()
        resultsById.removeAll()

        indexStudents(context: context)
        indexLessons(context: context)
        indexNotes(context: context)
        indexTodos(context: context)
        indexWork(context: context)

        isReady = true
        let elapsed = Date().timeIntervalSince(start)
        Self.logger.info("Search index built: \(self.resultsById.count) entities, \(self.index.count) tokens in \(String(format: "%.2f", elapsed))s")
    }

    // Deprecated SwiftData rebuildIndex(container:) removed - use rebuildIndex(context:) with NSManagedObjectContext.

    // MARK: - Incremental Updates

    func indexResult(_ result: SearchResult, text: String) {
        resultsById[result.id] = result
        for token in tokenize(text) {
            index[token, default: []].insert(result)
        }
    }

    func removeResult(id: UUID) {
        guard let result = resultsById.removeValue(forKey: id) else { return }
        for (token, var set) in index {
            set.remove(result)
            if set.isEmpty {
                index.removeValue(forKey: token)
            } else {
                index[token] = set
            }
        }
    }

    // MARK: - Search

    func search(
        query: String,
        entityTypes: Set<SearchableEntityType>? = nil,
        limit: Int = 50
    ) -> [SearchResult] {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return [] }

        // Start with the smallest token set for efficiency
        let sortedTokenSets = tokens.compactMap { token -> Set<SearchResult>? in
            // Support prefix matching
            let matches = index.keys.filter { $0.hasPrefix(token) }
            guard !matches.isEmpty else { return nil }
            var combined = Set<SearchResult>()
            for key in matches {
                if let set = index[key] {
                    combined.formUnion(set)
                }
            }
            return combined
        }

        guard let first = sortedTokenSets.min(by: { $0.count < $1.count }) else { return [] }

        // Intersect all token sets
        var candidates = first
        for (i, set) in sortedTokenSets.enumerated() {
            if set != first || i > 0 {
                candidates.formIntersection(set)
            }
        }

        // Filter by entity type if specified
        if let types = entityTypes {
            candidates = candidates.filter { types.contains($0.entityType) }
        }

        // Rank by number of matching tokens (more tokens = better match)
        let ranked = candidates.sorted { a, b in
            let aScore = tokens.filter { token in
                index.keys.contains(where: { $0.hasPrefix(token) && (index[$0]?.contains(a) ?? false) })
            }.count
            let bScore = tokens.filter { token in
                index.keys.contains(where: { $0.hasPrefix(token) && (index[$0]?.contains(b) ?? false) })
            }.count
            return aScore > bScore
        }

        return Array(ranked.prefix(limit))
    }

    // MARK: - Core Data Private Indexing

    private func indexStudents(context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDStudent.self)
        let students = context.safeFetch(request)
        for student in students {
            guard let studentID = student.id else { continue }
            let text = "\(student.firstName) \(student.lastName) \(student.nickname ?? "")"
            let result = SearchResult(
                id: studentID,
                entityType: .student,
                title: student.fullName,
                snippet: student.level.rawValue
            )
            indexResult(result, text: text)
        }
    }

    private func indexLessons(context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDLesson.self)
        let lessons = context.safeFetch(request)
        for lesson in lessons {
            guard let lessonID = lesson.id else { continue }
            let text = "\(lesson.name) \(lesson.subject) \(lesson.group) \(lesson.subheading)"
            let result = SearchResult(
                id: lessonID,
                entityType: .lesson,
                title: lesson.name,
                snippet: lesson.subject
            )
            indexResult(result, text: text)
        }
    }

    private func indexNotes(context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDNote.self)
        let notes = context.safeFetch(request)
        for note in notes {
            guard let noteID = note.id else { continue }
            let tags = (note.tags as? [String]) ?? []
            let body = note.body
            let text = "\(body) \(tags.joined(separator: " "))"
            let result = SearchResult(
                id: noteID,
                entityType: .note,
                title: String(body.prefix(80)),
                snippet: tags.first ?? ""
            )
            indexResult(result, text: text)
        }
    }

    private func indexTodos(context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDTodoItemEntity.self)
        let todos = context.safeFetch(request)
        for todo in todos {
            guard let todoID = todo.id else { continue }
            let text = "\(todo.title) \(todo.notes)"
            let result = SearchResult(
                id: todoID,
                entityType: .todo,
                title: todo.title,
                snippet: todo.notes
            )
            indexResult(result, text: text)
        }
    }

    private func indexWork(context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDWorkModel.self)
        let items = context.safeFetch(request)
        for work in items {
            guard let workID = work.id else { continue }
            let text = "\(work.title)"
            let result = SearchResult(
                id: workID,
                entityType: .work,
                title: work.title,
                snippet: work.status.rawValue
            )
            indexResult(result, text: text)
        }
    }

    // Deprecated SwiftData legacy indexing methods removed - Core Data versions are used.

    // MARK: - Tokenization

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }
}
