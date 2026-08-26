import Foundation
import Testing
@testable import Maria_s_Notebook

/// Covers the query semantics of the in-memory inverted index: prefix matching,
/// multi-token intersection, relevance ranking, entity-type filtering, and the
/// result limit. Written alongside a rewrite of `search()`'s ranking pass, which
/// previously scored inside the sort comparator and rescanned the whole vocabulary
/// per comparison — these pin the behavior that rewrite had to preserve.
///
/// `SearchIndexService` is a `private init` singleton, so each test starts by
/// purging the shared instance. Serialized so a purge can't land mid-query in a
/// sibling test.
@Suite("SearchIndexService", .serialized)
@MainActor
struct SearchIndexServiceTests {

    private func freshIndex() -> SearchIndexService {
        let index = SearchIndexService.shared
        index.purge()
        return index
    }

    private func result(
        _ title: String,
        _ type: SearchableEntityType = .note,
        snippet: String = ""
    ) -> SearchResult {
        SearchResult(id: UUID(), entityType: type, title: title, snippet: snippet)
    }

    @Test("finds a result by whole token and by prefix")
    func prefixAndExactMatching() {
        let index = freshIndex()
        let binomial = result("Binomial Cube")
        index.indexResult(binomial, text: "Binomial Cube sensorial material")

        #expect(index.search(query: "binomial").contains(binomial))
        #expect(index.search(query: "binom").contains(binomial))
        #expect(index.search(query: "sensor").contains(binomial))
        #expect(index.search(query: "trinomial").isEmpty)
    }

    @Test("multiple query tokens intersect rather than union")
    func multipleTokensIntersect() {
        let index = freshIndex()
        let both = result("Golden Beads")
        let onlyGolden = result("Golden Mat")
        let onlyBeads = result("Bead Chain")
        index.indexResult(both, text: "golden beads decimal system")
        index.indexResult(onlyGolden, text: "golden mat layout")
        index.indexResult(onlyBeads, text: "beads chain skip counting")

        let hits = index.search(query: "golden beads")
        #expect(hits.contains(both))
        #expect(!hits.contains(onlyGolden))
        #expect(!hits.contains(onlyBeads))
    }

    /// Every survivor of the intersection matches all query tokens by construction, so
    /// relevance scores are always tied and ranking cannot reorder anything. This pins
    /// that reality: adding a token narrows the result set, it does not re-rank it.
    @Test("extra query tokens narrow the result set rather than reordering it")
    func extraTokensNarrowRatherThanRank() {
        let index = freshIndex()
        let withBox = result("Grammar Symbols Box")
        let withoutBox = result("Grammar Farm")
        index.indexResult(withBox, text: "grammar symbols box language")
        index.indexResult(withoutBox, text: "grammar farm language symbols")

        // Both carry "grammar" and "symbols", so both survive.
        #expect(Set(index.search(query: "grammar symbols")) == Set([withBox, withoutBox]))

        // "box" is unique to one, so the intersection drops the other outright.
        #expect(index.search(query: "grammar box") == [withBox])
    }

    /// Long-standing behavior, pinned here because it is surprising: a query token that
    /// matches nothing in the corpus is dropped rather than emptying the result set, so
    /// "grammar trinomial" still returns every grammar hit. Narrowing a search with a
    /// word no document contains silently does nothing. Worth revisiting as a product
    /// question — this test documents the status quo, it does not endorse it.
    @Test("a query token matching nothing is ignored instead of eliminating results")
    func unmatchedQueryTokenIsIgnored() {
        let index = freshIndex()
        let grammar = result("Grammar Symbols Box")
        index.indexResult(grammar, text: "grammar symbols box language")

        #expect(index.search(query: "grammar") == [grammar])
        #expect(index.search(query: "grammar trinomial") == [grammar])
        // Only when no token matches at all does the search come back empty.
        #expect(index.search(query: "trinomial").isEmpty)
    }

    @Test("entityTypes filter restricts results to the requested kinds")
    func entityTypeFiltering() {
        let index = freshIndex()
        let note = result("Practical Life", .note)
        let lesson = result("Practical Life", .lesson)
        index.indexResult(note, text: "practical life pouring")
        index.indexResult(lesson, text: "practical life pouring")

        #expect(Set(index.search(query: "pouring")) == Set([note, lesson]))
        #expect(index.search(query: "pouring", entityTypes: [.lesson]) == [lesson])
        #expect(index.search(query: "pouring", entityTypes: [.note]) == [note])
        #expect(index.search(query: "pouring", entityTypes: [.student]).isEmpty)
    }

    @Test("limit caps the number of results returned")
    func limitCapsResults() {
        let index = freshIndex()
        for number in 0..<25 {
            index.indexResult(result("Card \(number)"), text: "counting card number \(number)")
        }
        #expect(index.search(query: "counting", limit: 10).count == 10)
        #expect(index.search(query: "counting", limit: 50).count == 25)
    }

    @Test("single-character and empty queries return nothing")
    func degenerateQueries() {
        let index = freshIndex()
        index.indexResult(result("Sandpaper Letters"), text: "sandpaper letters language")
        // `tokenize` drops tokens shorter than 2 characters.
        #expect(index.search(query: "s").isEmpty)
        #expect(index.search(query: "").isEmpty)
        #expect(index.search(query: "   ").isEmpty)
    }

    /// A result indexed twice under the same id — which is what a rebuild after an
    /// edit produces — must resolve to the current value, not a stale copy left behind
    /// in a token bucket.
    @Test("re-indexing the same id returns the newest result, not a stale copy")
    func reindexingReplacesStaleResult() {
        let index = freshIndex()
        let id = UUID()
        let before = SearchResult(id: id, entityType: .note, title: "Draft title", snippet: "")
        let after = SearchResult(id: id, entityType: .note, title: "Final title", snippet: "")
        index.indexResult(before, text: "shared observation text")
        index.indexResult(after, text: "shared observation text")

        let hits = index.search(query: "observation")
        #expect(hits.count == 1)
        #expect(hits.first?.title == "Final title")
    }

    @Test("purge empties the index and clears readiness")
    func purgeClearsEverything() {
        let index = freshIndex()
        index.indexResult(result("Moveable Alphabet"), text: "moveable alphabet language")
        #expect(!index.search(query: "alphabet").isEmpty)

        index.purge()
        #expect(index.search(query: "alphabet").isEmpty)
        #expect(!index.isReady)
    }
}
