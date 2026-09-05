import Foundation
import CoreData
import OSLog

/// Entity types that can be indexed for full-text search.
enum SearchableEntityType: String, CaseIterable, Sendable, Codable {
    case note, lesson, student, todo, work
}

/// A lightweight search result reference.
nonisolated struct SearchResult: Hashable, Identifiable, Sendable, Codable {
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

/// The two dictionaries the index is made of, as a value so they can be built
/// off the main actor and handed over in one assignment.
nonisolated struct SearchIndexContents: Sendable {
    /// Token -> ids of matching results.
    ///
    /// Stores ids rather than whole `SearchResult` values: a result is duplicated into
    /// a bucket for every distinct token in its text, so holding the struct meant
    /// carrying two refcounted `String` fields per (token, result) pair across the
    /// whole corpus — the index's dominant cost, in bytes and in ARC traffic on every
    /// union and intersection. `resultsById` is the single owner of the values.
    var index: [String: Set<UUID>] = [:]

    /// All indexed results by ID — the authoritative store, and the lookup that turns
    /// a set of matching ids back into results.
    var resultsById: [UUID: SearchResult] = [:]

    mutating func add(_ result: SearchResult, text: String) {
        resultsById[result.id] = result
        for token in SearchIndexService.tokenize(text) {
            index[token, default: []].insert(result.id)
        }
    }
}

/// In-memory inverted index for full-text search across all searchable entities.
///
/// Built from an on-disk snapshot plus persistent history at launch (see
/// `SearchIndexService+Snapshot.swift`), or from a full Core Data pass when no
/// usable snapshot exists. Search runs on the main actor; every fetch, decode,
/// and tokenization pass runs off it.
@Observable
final class SearchIndexService {
    static let shared = SearchIndexService()
    nonisolated static let logger = Logger.app(category: "SearchIndex")

    /// How the most recent refresh produced its contents.
    enum RefreshSource: String, Sendable {
        /// The on-disk snapshot, with no searchable changes since it was written.
        case snapshot
        /// The snapshot patched with persistent-history changes.
        case incremental
        /// A full pass over every searchable entity.
        case fullRebuild
    }

    private var index: [String: Set<UUID>] = [:]
    private var resultsById: [UUID: SearchResult] = [:]

    private(set) var isReady = false

    /// Diagnostics for the last `refresh` / rebuild; `nil` until one has run.
    private(set) var lastRefreshSource: RefreshSource?

    /// Where snapshots are written. `nil` keeps the index memory-only.
    let snapshotDirectory: URL?

    /// Above this many searchable inserts, updates, and deletes since the
    /// snapshot, replaying history costs more than a fresh pass; rebuild instead.
    let incrementalChangeLimit: Int

    /// Container used for the last build, so a purged index can rebuild itself
    /// without every caller having to thread a container through.
    private weak var indexingContainer: NSPersistentContainer?

    init(
        snapshotDirectory: URL? = SearchIndexSnapshotStore.defaultDirectory,
        incrementalChangeLimit: Int = 2_000
    ) {
        self.snapshotDirectory = snapshotDirectory
        self.incrementalChangeLimit = incrementalChangeLimit
    }

    // MARK: - Memory Pressure

    /// Drops the entire inverted index.
    ///
    /// The index is a full-corpus structure with no eviction path, so under real
    /// memory pressure it's the largest thing this app can hand back. Call
    /// `ensureReady()` before searching — it reloads lazily on the next use.
    func purge() {
        guard isReady || !index.isEmpty else { return }
        let freedTokens = index.count
        index.removeAll()
        resultsById.removeAll()
        isReady = false
        Self.logger.info("Search index purged under memory pressure (\(freedTokens) tokens released)")
    }

    /// Refreshes the index if it has never been built or was purged. No-op once ready.
    func ensureReady() async {
        guard !isReady, let container = indexingContainer else { return }
        await refresh(container: container)
    }

    // MARK: - Building

    /// Launch-time entry point. Reuses the on-disk snapshot when it belongs to
    /// this store, replays persistent history recorded since it was written, and
    /// falls back to a full rebuild otherwise. The fetches, the decode, and the
    /// tokenization all run off the main actor; only the final assignment lands here.
    func refresh(container: NSPersistentContainer) async {
        indexingContainer = container
        let outcome = await Self.refreshContents(
            context: container.newBackgroundContext(),
            identity: Self.storeIdentity(of: container),
            currentToken: Self.archivedCurrentHistoryToken(of: container),
            snapshotDirectory: snapshotDirectory,
            changeLimit: incrementalChangeLimit
        )
        apply(outcome)
    }

    /// Unconditional full pass over every searchable entity on a background
    /// context, then a snapshot write so the next launch can skip it.
    func rebuildIndexAsync(container: NSPersistentContainer) async {
        indexingContainer = container
        let outcome = await Self.fullRebuild(
            context: container.newBackgroundContext(),
            identity: Self.storeIdentity(of: container),
            currentToken: Self.archivedCurrentHistoryToken(of: container),
            snapshotDirectory: snapshotDirectory
        )
        apply(outcome)
    }

    /// Rebuild synchronously on the caller's context, without touching the snapshot.
    /// Prefer `refresh(container:)` at launch so nothing blocks the main thread.
    func rebuildIndex(context: NSManagedObjectContext) {
        let start = Date()
        let entries = Self.collectAllEntries(context: context)
        apply(SearchIndexRefreshOutcome(contents: Self.buildContents(from: entries), source: .fullRebuild))
        let elapsed = Date().timeIntervalSince(start)
        Self.logger.info("Search index built synchronously in \(String(format: "%.2f", elapsed))s")
    }

    private func apply(_ outcome: SearchIndexRefreshOutcome) {
        index = outcome.contents.index
        resultsById = outcome.contents.resultsById
        isReady = true
        lastRefreshSource = outcome.source
        let count = resultsById.count
        let tokens = index.count
        let source = outcome.source.rawValue
        Self.logger.info("Search index ready (\(source, privacy: .public)): \(count) entities, \(tokens) tokens")
    }

    // MARK: - Incremental Updates

    func indexResult(_ result: SearchResult, text: String) {
        resultsById[result.id] = result
        for token in Self.tokenize(text) {
            index[token, default: []].insert(result.id)
        }
    }

    // MARK: - Search

    func search(
        query: String,
        entityTypes: Set<SearchableEntityType>? = nil,
        limit: Int = 50
    ) -> [SearchResult] {
        let tokens = Self.tokenize(query)
        guard !tokens.isEmpty else { return [] }

        // One vocabulary scan per query token, reused for both matching and ranking.
        // Iterating key/value pairs avoids the intermediate `[String]` from
        // `index.keys.filter` and the second hash lookup per key.
        let tokenMatches: [Set<UUID>] = tokens.compactMap { token in
            var combined = Set<UUID>()
            for (key, ids) in index where key.hasPrefix(token) {
                combined.formUnion(ids)
            }
            return combined.isEmpty ? nil : combined
        }

        // Intersect, starting from the smallest set so the first pass does the most work.
        guard let smallest = tokenMatches.min(by: { $0.count < $1.count }) else { return [] }
        var candidates = smallest
        for set in tokenMatches {
            candidates.formIntersection(set)
        }

        // Filter by entity type if specified
        if let types = entityTypes {
            candidates = candidates.filter { id in
                guard let type = resultsById[id]?.entityType else { return false }
                return types.contains(type)
            }
        }

        // Ranking by "number of matching query tokens" is vestigial: `candidates` is
        // the intersection of every token's match set, so each survivor matches all of
        // them and every score is identical. It was already a tie before this rewrite —
        // but it was an expensive one. The old code scored inside the sort comparator,
        // recomputing both operands on every comparison, and each score rescanned the
        // entire vocabulary (`index.keys.contains(where:)`) once per query token:
        // O(candidates · log(candidates) · tokens · vocabulary) on the main actor, for a
        // view that searches on every keystroke.
        //
        // Kept as a cheap explicit pass rather than deleted, so that relaxing the
        // intersection above (to OR/fuzzy matching) starts ranking for real instead of
        // silently returning an arbitrary set order.
        let ranked = candidates
            .compactMap { id -> (result: SearchResult, score: Int)? in
                guard let result = resultsById[id] else { return nil }
                return (result, tokenMatches.reduce(0) { $0 + ($1.contains(id) ? 1 : 0) })
            }
            .sorted { $0.score > $1.score }
            .map(\.result)

        return Array(ranked.prefix(limit))
    }

    // MARK: - Tokenization

    nonisolated static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }
}
