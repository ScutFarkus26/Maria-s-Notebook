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
    let date: Date?

    init(
        id: UUID,
        entityType: SearchableEntityType,
        title: String,
        snippet: String,
        date: Date? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.title = title
        self.snippet = snippet
        self.date = date
    }

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

    /// Container used for the last build, so a purged index can rebuild itself
    /// without every caller having to thread a container through.
    private weak var indexingContainer: NSPersistentContainer?

    private init() {}

    // MARK: - Memory Pressure

    /// Drops the entire inverted index.
    ///
    /// The index is a full-corpus structure with no eviction path, so under real
    /// memory pressure it's the largest thing this app can hand back. Call
    /// `ensureReady()` before searching — it rebuilds lazily on the next use.
    func purge() {
        guard isReady || !index.isEmpty else { return }
        let freedTokens = index.count
        index.removeAll()
        resultsById.removeAll()
        isReady = false
        Self.logger.info("Search index purged under memory pressure (\(freedTokens) tokens released)")
    }

    /// Rebuilds the index if it has never been built or was purged. No-op once ready.
    func ensureReady() async {
        guard !isReady, let container = indexingContainer else { return }
        await rebuildIndexAsync(container: container)
    }

    // MARK: - Core Data Index Building

    /// Rebuild the index synchronously on the provided context's queue.
    /// Prefer `rebuildIndexAsync(container:)` at launch to avoid blocking the main thread.
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
        let indexMsg = "Search index built: \(self.resultsById.count) entities, " +
            "\(self.index.count) tokens in \(String(format: "%.2f", elapsed))s"
        Self.logger.info("\(indexMsg, privacy: .public)")
    }

    /// Rebuild the index using a background context so the main thread is free during fetches.
    /// Collected (SearchResult, text) pairs are applied on the main actor once fetching completes.
    func rebuildIndexAsync(container: NSPersistentContainer) async {
        indexingContainer = container
        let bgContext = container.newBackgroundContext()
        // Collect all entity data as value types on the background context's queue.
        let collected: [(SearchResult, String)] = await bgContext.perform {
            Self.collectAll(context: bgContext)
        }
        // Apply results on the main actor — index storage is @MainActor.
        index.removeAll()
        resultsById.removeAll()
        for (result, text) in collected {
            indexResult(result, text: text)
        }
        isReady = true
        let count = resultsById.count
        let tokens = index.count
        Self.logger.info("Search index built (async): \(count) entities, \(tokens) tokens")
    }

    // MARK: - Background Collection (nonisolated static — safe to call inside bgContext.perform)

    /// Gathers all indexable entities from the given context and returns Sendable value pairs.
    private nonisolated static func collectAll(context: NSManagedObjectContext) -> [(SearchResult, String)] {
        var pairs: [(SearchResult, String)] = []
        collectStudents(context: context, into: &pairs)
        collectLessons(context: context, into: &pairs)
        collectNotes(context: context, into: &pairs)
        collectTodos(context: context, into: &pairs)
        collectWork(context: context, into: &pairs)
        return pairs
    }

    private nonisolated static func collectStudents(
        context: NSManagedObjectContext,
        into pairs: inout [(SearchResult, String)]
    ) {
        let request = CDFetchRequest(CDStudent.self)
        for student in context.safeFetch(request) {
            guard let id = student.id else { continue }
            pairs.append((
                SearchResult(id: id, entityType: .student, title: student.fullName, snippet: student.level.rawValue),
                "\(student.firstName) \(student.lastName) \(student.nickname ?? "")"
            ))
        }
    }

    private nonisolated static func collectLessons(
        context: NSManagedObjectContext,
        into pairs: inout [(SearchResult, String)]
    ) {
        let request = CDFetchRequest(CDLesson.self)
        for lesson in context.safeFetch(request) {
            guard let id = lesson.id else { continue }
            pairs.append((
                SearchResult(id: id, entityType: .lesson, title: lesson.name, snippet: lesson.area),
                "\(lesson.name) \(lesson.area) \(lesson.sequence) \(lesson.section)"
            ))
        }
    }

    private nonisolated static func collectNotes(
        context: NSManagedObjectContext,
        into pairs: inout [(SearchResult, String)]
    ) {
        let request = CDFetchRequest(CDNote.self)
        for note in context.safeFetch(request) {
            guard let id = note.id else { continue }
            let tags = (note.tags as? [String]) ?? []
            let body = note.body
            pairs.append((
                SearchResult(
                    id: id, entityType: .note,
                    title: String(body.prefix(80)), snippet: tags.first ?? "", date: note.createdAt
                ),
                "\(body) \(tags.joined(separator: " "))"
            ))
        }
    }

    private nonisolated static func collectTodos(
        context: NSManagedObjectContext,
        into pairs: inout [(SearchResult, String)]
    ) {
        let request = CDFetchRequest(CDTodoItemEntity.self)
        for todo in context.safeFetch(request) {
            guard let id = todo.id else { continue }
            pairs.append((
                SearchResult(
                    id: id, entityType: .todo,
                    title: todo.title, snippet: todo.notes, date: todo.createdAt
                ),
                "\(todo.title) \(todo.notes)"
            ))
        }
    }

    private nonisolated static func collectWork(
        context: NSManagedObjectContext,
        into pairs: inout [(SearchResult, String)]
    ) {
        let request = CDFetchRequest(CDWorkModel.self)
        for work in context.safeFetch(request) {
            guard let id = work.id else { continue }
            pairs.append((
                SearchResult(
                    id: id, entityType: .work,
                    title: work.title, snippet: work.status.rawValue, date: work.createdAt
                ),
                work.title
            ))
        }
    }

    // Deprecated SwiftData rebuildIndex(container:) removed - use rebuildIndex(context:) with NSManagedObjectContext.

    // MARK: - Incremental Updates

    func indexResult(_ result: SearchResult, text: String) {
        resultsById[result.id] = result
        for token in tokenize(text) {
            index[token, default: []].insert(result)
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
            let text = "\(lesson.name) \(lesson.area) \(lesson.sequence) \(lesson.section)"
            let result = SearchResult(
                id: lessonID,
                entityType: .lesson,
                title: lesson.name,
                snippet: lesson.area
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
                snippet: tags.first ?? "",
                date: note.createdAt
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
                snippet: todo.notes,
                date: todo.createdAt
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
                snippet: work.status.rawValue,
                date: work.createdAt
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
