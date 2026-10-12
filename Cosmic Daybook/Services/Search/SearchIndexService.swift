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

    /// `NSManagedObjectID.uriRepresentation()` of each indexed object -> its
    /// result id. Persistent history names a deleted object only by its object
    /// ID, so this is how an in-session delete finds the result to drop.
    var idsByURI: [String: UUID] = [:]

    mutating func add(_ result: SearchResult, text: String, objectURI: String? = nil) {
        resultsById[result.id] = result
        if let objectURI { idsByURI[objectURI] = result.id }
        for token in SearchIndexService.tokenize(text) {
            index[token, default: []].insert(result.id)
        }
    }

    /// Drops `ids` from every bucket and from `resultsById`, and forgets
    /// `objectURIs`. One pass over the vocabulary however many ids go, since
    /// the index keeps no per-result token list to walk instead.
    mutating func remove(ids: Set<UUID>, objectURIs: some Sequence<String>) {
        for uri in objectURIs {
            idsByURI.removeValue(forKey: uri)
        }
        guard !ids.isEmpty else { return }
        for id in ids {
            resultsById.removeValue(forKey: id)
        }
        let affected = index.compactMap { token, bucket in bucket.isDisjoint(with: ids) ? nil : token }
        for token in affected {
            index[token]?.subtract(ids)
            if index[token]?.isEmpty == true {
                index.removeValue(forKey: token)
            }
        }
    }
}

/// In-memory inverted index for full-text search across all searchable entities.
///
/// Built from an on-disk snapshot plus persistent history at launch (see
/// `SearchIndexService+Snapshot.swift`), or from a full Core Data pass when no
/// usable snapshot exists, then kept current during the session by replaying
/// the history recorded since (see `SearchIndexService+CatchUp.swift`).
/// Search runs on the main actor; every fetch, decode, and tokenization pass
/// runs off it.
@Observable
final class SearchIndexService {
    static let shared = SearchIndexService()
    nonisolated static let logger = Logger.searchIndex

    /// How the most recent refresh produced its contents.
    enum RefreshSource: String, Sendable {
        /// The on-disk snapshot, with no searchable changes since it was written.
        case snapshot
        /// The snapshot patched with persistent-history changes.
        case incremental
        /// A full pass over every searchable entity.
        case fullRebuild
    }

    // `private(set)` (not `private`) so the equivalence tests can replay the
    // pre-2026-09-22 linear scan against the same index.
    private(set) var index: [String: Set<UUID>] = [:]
    private(set) var resultsById: [UUID: SearchResult] = [:]
    @ObservationIgnored var idsByURI: [String: UUID] = [:]

    /// The index's tokens in `String` order, so a prefix query is a binary
    /// search instead of a `hasPrefix` test against every token in the corpus
    /// on every keystroke. `nil` when the vocabulary has changed since the last
    /// sort; rebuilt on the next search.
    @ObservationIgnored private var sortedTokens: [String]?

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
    weak var indexingContainer: NSPersistentContainer?

    // MARK: In-session catch-up state (see `SearchIndexService+CatchUp.swift`)

    /// Archived history token the index is current to; `nil` until a refresh
    /// has run, and after a purge.
    @ObservationIgnored var indexedHistoryToken: Data?

    /// Bumped whenever the contents are replaced wholesale (refresh, purge), so
    /// a catch-up computed against the old contents is discarded, not applied.
    @ObservationIgnored var contentsGeneration = 0

    /// How long a burst of store changes is coalesced before the index replays it.
    let catchUpDelay: Duration

    @ObservationIgnored var catchUpTask: Task<Void, Never>?
    /// The build under way (the launch refresh or a first search's), shared
    /// by every caller that arrives while it runs, and the container it reads.
    @ObservationIgnored private var pendingBuild: Task<Void, Never>?
    @ObservationIgnored private weak var pendingBuildContainer: NSPersistentContainer?
    @ObservationIgnored var scheduledCatchUp: Task<Void, Never>?
    @ObservationIgnored var followTask: Task<Void, Never>?
    @ObservationIgnored weak var followedCoordinator: NSPersistentStoreCoordinator?

    /// Diagnostics: how many in-session history replays have run. The token
    /// gate keeps this still when nothing was written.
    @ObservationIgnored var catchUpPasses = 0

    init(
        snapshotDirectory: URL? = SearchIndexSnapshotStore.defaultDirectory,
        incrementalChangeLimit: Int = 2_000,
        catchUpDelay: Duration = .seconds(2)
    ) {
        self.snapshotDirectory = snapshotDirectory
        self.incrementalChangeLimit = incrementalChangeLimit
        self.catchUpDelay = catchUpDelay
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
        idsByURI.removeAll()
        sortedTokens = nil
        isReady = false
        indexedHistoryToken = nil
        contentsGeneration += 1
        Self.logger.info("Search index purged under memory pressure (\(freedTokens) tokens released)")
    }

    /// Refreshes the index if it has never been built or was purged; once
    /// ready, replays whatever was written since it was last brought current,
    /// so a search right after a save or delete sees it. The replay is gated
    /// on the history token, so with nothing new it costs one token read.
    ///
    /// After a deferred launch (see `adopt`) the first call is the build.
    /// Callers arriving while a build runs (the Search sheet and a chat
    /// answer at once, or either during the launch refresh) wait for it
    /// rather than each starting their own (see `refresh`).
    func ensureReady() async {
        guard let container = indexingContainer else { return }
        if isReady {
            await catchUp()
        } else {
            await refresh(container: container)
        }
    }

    /// Points the index at `container` without building it: a launch on a
    /// hot device or in Low Power Mode leaves the build to the first search,
    /// which `ensureReady()` runs from the on-disk snapshot when there is
    /// one. Without this nothing set the container on such a launch, so
    /// search, chat and MCP `search_notebook` found nothing all session
    /// (bug hunt 2026-10-11 #43).
    func adopt(_ container: NSPersistentContainer) {
        indexingContainer = container
    }

    // MARK: - Building

    /// Launch-time entry point. Reuses the on-disk snapshot when it belongs to
    /// this store, replays persistent history recorded since it was written, and
    /// falls back to a full rebuild otherwise. The fetches, the decode, and the
    /// tokenization all run off the main actor; only the final assignment lands here.
    ///
    /// A call while a build of the same container runs waits for that build
    /// instead of starting another. The launch called this directly, so a
    /// search (Search screen, MCP `search_notebook`, chat) during the launch
    /// refresh ran a second full refresh beside it, and both wrote the
    /// snapshot (review (b) 2026-10-11).
    func refresh(container: NSPersistentContainer) async {
        indexingContainer = container
        while let pending = pendingBuild {
            let sameContainer = pendingBuildContainer === container
            await pending.value
            if sameContainer { return }
        }
        let build = Task { [weak self] in
            guard let self else { return }
            await self.build(container: container)
        }
        pendingBuild = build
        pendingBuildContainer = container
        await build.value
        if pendingBuild == build {
            pendingBuild = nil
            pendingBuildContainer = nil
        }
    }

    /// One refresh pass; `refresh` makes sure only one runs at a time.
    private func build(container: NSPersistentContainer) async {
        follow(container)
        let currentToken = Self.archivedCurrentHistoryToken(of: container)
        let outcome = await Self.refreshContents(
            context: container.newBackgroundContext(),
            identity: Self.storeIdentity(of: container),
            currentToken: currentToken,
            snapshotDirectory: snapshotDirectory,
            changeLimit: incrementalChangeLimit
        )
        apply(outcome)
        // Everything up to `currentToken` is in the contents now (it was read
        // before the fetches), so the in-session replay starts there.
        indexedHistoryToken = currentToken
    }

    private func apply(_ outcome: SearchIndexRefreshOutcome) {
        setContents(outcome.contents)
        contentsGeneration += 1
        isReady = true
        lastRefreshSource = outcome.source
        let count = resultsById.count
        let tokens = index.count
        let source = outcome.source.rawValue
        Self.logger.info("Search index ready (\(source, privacy: .public)): \(count) entities, \(tokens) tokens")
    }

    func setContents(_ contents: SearchIndexContents) {
        index = contents.index
        resultsById = contents.resultsById
        idsByURI = contents.idsByURI
        sortedTokens = nil
    }

    var contents: SearchIndexContents {
        SearchIndexContents(index: index, resultsById: resultsById, idsByURI: idsByURI)
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
            for key in keys(withPrefix: token) {
                if let ids = index[key] { combined.formUnion(ids) }
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

        // Every survivor matches all the query tokens, so there is no score to
        // rank by. The order is by kind (students, then lessons, then
        // everything else), then newest first; it used to be a Set's, and the
        // limit kept an arbitrary 50 (or 8 for chat and MCP), so the child's
        // own row could be missing (bug hunt 2026-10-11 #44).
        let ranked = candidates
            .compactMap { resultsById[$0] }
            .sorted(by: Self.ranksBefore)
        return Array(ranked.prefix(limit))
    }

    /// Search order: students, then lessons, then notes, todos and work
    /// together; newest first within each, undated last; then by title and id,
    /// so the same index always gives the same order.
    nonisolated static func ranksBefore(_ lhs: SearchResult, _ rhs: SearchResult) -> Bool {
        let lhsKind = kindRank(lhs.entityType)
        let rhsKind = kindRank(rhs.entityType)
        if lhsKind != rhsKind { return lhsKind < rhsKind }
        switch (lhs.date, rhs.date) {
        case let (left?, right?) where left != right: return left > right
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        let order = lhs.title.localizedStandardCompare(rhs.title)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func kindRank(_ type: SearchableEntityType) -> Int {
        switch type {
        case .student: 0
        case .lesson: 1
        case .note, .todo, .work: 2
        }
    }

    /// Every token in the index with `prefix` as a `hasPrefix` prefix — the
    /// same keys the linear scan found (in sorted rather than dictionary order;
    /// they are only ever unioned into a `Set`).
    ///
    /// `String` ordering compares canonically normalised scalars, so every
    /// token that starts with `prefix` sorts in `[prefix, prefix + U+10FFFF)`;
    /// `hasPrefix` still has the last word inside that range.
    func keys(withPrefix prefix: String) -> [String] {
        let sorted: [String]
        if let cached = sortedTokens {
            sorted = cached
        } else {
            sorted = index.keys.sorted()
            sortedTokens = sorted
        }
        let lower = Self.lowerBound(of: prefix, in: sorted)
        let upper = Self.lowerBound(of: prefix + "\u{10FFFF}", in: sorted)
        guard lower < upper else { return [] }
        return sorted[lower..<upper].filter { $0.hasPrefix(prefix) }
    }
}
