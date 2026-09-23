import Foundation
import Testing
@testable import CosmicDaybook

/// Pins that the binary-search prefix lookup returns exactly what the linear
/// `hasPrefix` scan over every token did — the same keys, and so the same
/// search results. (Result *order* is a `Set`'s iteration order, which Swift
/// seeds per instance, so it was never stable between two identical searches;
/// results are compared as sets, and by count where the limit cuts them.)
@MainActor
struct SearchIndexPrefixLookupTests {

    private static let corpus: [String] = [
        "Golden bead addition with the large bead frame",
        "Stamp game subtraction; dynamic stamp game",
        "Sandpaper letters s, m, a — phonogram work",
        "Café reflection: crème brûlée, naïve résumé",
        "Cafe au lait and cafés; ÉCOLE école Ecole",
        "Numbers 100 1000 10000 and 2x2 3x3 checkerboard",
        "Zoë, Zoe and Zoey worked on the Hebrew aleph-bet: אלף בית",
        "Japanese かな カナ 漢字 and 漢字練習",
        "q\u{301}uick combining marks e\u{301}clair and e\u{0301}e\u{0301}",
        "Fractions: ½ ¾ insets, fraction circles, fractional",
        "Timeline of life; time telling; timer; timid",
        "aa ab abc abd abe b ba bab", "zz zzz zzzz",
        "Ümlaut über Übung uber",
        "Emoji 🎉 party and test👩‍🏫teacher"
    ]

    private static let queries: [String] = [
        "go", "gold", "bead", "be", "st", "sta", "stamp game", "caf", "café", "cafe", "cr", "écol", "ec",
        "10", "100", "1000", "2x", "zo", "zoë", "zoe", "אל", "かな", "漢字", "q\u{301}", "qu", "e\u{301}", "ec",
        "fr", "frac", "ti", "tim", "time", "aa", "ab", "abc", "b", "ba", "zz", "zzz", "über", "ub", "üb",
        "no match here", "xy", "te", "teacher", "party", "a b", "ab ba"
    ]

    private func makeIndex() -> SearchIndexService {
        let service = SearchIndexService(snapshotDirectory: nil)
        for (i, text) in Self.corpus.enumerated() {
            for copy in 0..<3 {
                let result = SearchResult(
                    id: UUID(),
                    entityType: SearchableEntityType.allCases[(i + copy) % SearchableEntityType.allCases.count],
                    title: "\(i)-\(copy)",
                    snippet: text
                )
                service.indexResult(result, text: copy == 2 ? text.uppercased() : text)
            }
        }
        return service
    }

    /// The pre-2026-09-22 per-token scan.
    private func legacyKeys(_ service: SearchIndexService, prefix: String) -> [String] {
        service.index.compactMap { key, _ in key.hasPrefix(prefix) ? key : nil }
    }

    /// The pre-2026-09-22 `search`, verbatim apart from reading the index from outside.
    private func legacySearch(
        _ service: SearchIndexService, query: String,
        entityTypes: Set<SearchableEntityType>? = nil, limit: Int = 50
    ) -> [SearchResult] {
        let tokens = SearchIndexService.tokenize(query)
        guard !tokens.isEmpty else { return [] }
        let tokenMatches: [Set<UUID>] = tokens.compactMap { token in
            var combined = Set<UUID>()
            for (key, ids) in service.index where key.hasPrefix(token) { combined.formUnion(ids) }
            return combined.isEmpty ? nil : combined
        }
        guard let smallest = tokenMatches.min(by: { $0.count < $1.count }) else { return [] }
        var candidates = smallest
        for set in tokenMatches { candidates.formIntersection(set) }
        if let types = entityTypes {
            candidates = candidates.filter { id in
                guard let type = service.resultsById[id]?.entityType else { return false }
                return types.contains(type)
            }
        }
        let ranked = candidates
            .compactMap { id -> (result: SearchResult, score: Int)? in
                guard let result = service.resultsById[id] else { return nil }
                return (result, tokenMatches.reduce(0) { $0 + ($1.contains(id) ? 1 : 0) })
            }
            .sorted { $0.score > $1.score }
            .map(\.result)
        return Array(ranked.prefix(limit))
    }

    @Test func prefixKeysMatchLinearScanInOrder() {
        let service = makeIndex()
        var nonEmpty = 0
        for query in Self.queries {
            for token in SearchIndexService.tokenize(query) + [query.lowercased()] {
                let fast = service.keys(withPrefix: token)
                #expect(fast.count == Set(fast).count)
                #expect(Set(fast) == Set(legacyKeys(service, prefix: token)), "\(token)")
                if !fast.isEmpty { nonEmpty += 1 }
            }
        }
        #expect(nonEmpty > 20)
    }

    @Test func searchResultsMatchLinearScan() {
        let service = makeIndex()
        var sawResults = false
        for query in Self.queries {
            let fast = service.search(query: query)
            let legacy = legacySearch(service, query: query)
            #expect(Set(fast.map(\.id)) == Set(legacy.map(\.id)), "\(query)")
            if !fast.isEmpty { sawResults = true }

            // Cut by the limit: which three survive was never defined, only how many.
            let cutFast = service.search(query: query, entityTypes: [.note, .lesson], limit: 3)
            let cutLegacy = legacySearch(service, query: query, entityTypes: [.note, .lesson], limit: 3)
            #expect(cutFast.count == cutLegacy.count, "\(query)")
            #expect(cutFast.allSatisfy { [.note, .lesson].contains($0.entityType) })
        }
        #expect(sawResults)
    }

    @Test func vocabularyChangesAreSeenAfterASearch() {
        let service = makeIndex()
        #expect(service.keys(withPrefix: "xylo").isEmpty)
        service.indexResult(SearchResult(id: UUID(), entityType: .lesson, title: "x", snippet: ""), text: "xylophone")
        #expect(service.keys(withPrefix: "xylo") == ["xylophone"])
        #expect(service.search(query: "xylo").count == 1)
        service.purge()
        #expect(service.keys(withPrefix: "xylo").isEmpty)
    }
}
