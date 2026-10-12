import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11, agent Q: search on a deferred launch (#43), ranking
/// (#44) and accents (#50).
@Suite("Search fixes (10-11 Q)")
@MainActor
struct SearchIndexFix1011Q {

    private func makeOnDiskStack() throws -> (stack: CoreDataStack, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stack = try CoreDataStack(
            enableCloudKit: false,
            localStoreURL: directory.appendingPathComponent("unified.sqlite")
        )
        return (stack, directory)
    }

    private func service(with entries: [(SearchResult, String)]) -> SearchIndexService {
        let service = SearchIndexService(snapshotDirectory: nil)
        var contents = SearchIndexContents()
        for (result, text) in entries {
            contents.add(result, text: text)
        }
        service.setContents(contents)
        return service
    }

    // MARK: #43

    @Test("A launch on a hot device or in Low Power Mode still lets the first search build the index")
    func deferredLaunchStillSearches() async throws {
        let (stack, directory) = try makeOnDiskStack()
        CoreDataTestHelpers.seedNote(in: stack.viewContext, body: "Stamp game with Maya")
        try #require(CoreDataTestHelpers.save(stack.viewContext))

        let index = SearchIndexService(snapshotDirectory: directory.appendingPathComponent("snapshots"))
        await AppBootstrapper.prepareSearchIndex(index, container: stack.container, deferMaintenance: true)
        // Nothing was built at launch: that is what deferring saves.
        #expect(!index.isReady)

        // The Search sheet, chat and MCP all call this before searching.
        await index.ensureReady()
        #expect(index.isReady)
        #expect(index.search(query: "stamp").map(\.title) == ["Stamp game with Maya"])
    }

    // MARK: #44

    @Test("Students come first, then lessons, then everything else newest first")
    func rankedByTypeThenNewest() throws {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        var entries: [(SearchResult, String)] = []
        // Sixty notes mentioning her, a day apart, inserted oldest first.
        for day in 0..<60 {
            let note = SearchResult(
                id: UUID(), entityType: .note, title: "Note \(day)", snippet: "",
                date: base.addingTimeInterval(Double(day) * 86_400)
            )
            entries.append((note, "Maya worked with the stamp game"))
        }
        let work = SearchResult(
            id: UUID(), entityType: .work, title: "Maya's stamp game work", snippet: "",
            date: base.addingTimeInterval(30.5 * 86_400)
        )
        entries.append((work, "Maya stamp game"))
        let lesson = SearchResult(id: UUID(), entityType: .lesson, title: "Maya lesson", snippet: "")
        entries.append((lesson, "Maya lesson"))
        let student = SearchResult(id: UUID(), entityType: .student, title: "Maya Sandler", snippet: "")
        entries.append((student, "Maya Sandler"))

        let results = service(with: entries).search(query: "maya", limit: 8)

        #expect(results.map(\.title) == [
            "Maya Sandler", "Maya lesson", "Note 59", "Note 58", "Note 57", "Note 56", "Note 55", "Note 54"
        ])
        // Work sits among the notes by its date, between Note 31 and Note 30.
        let all = service(with: entries).search(query: "maya", limit: 70)
        let workIndex = try #require(all.firstIndex { $0.id == work.id })
        #expect(all[workIndex - 1].title == "Note 31")
        #expect(all[workIndex + 1].title == "Note 30")
        #expect(all.count == 63)
    }

    // MARK: #50

    @Test("Search ignores accents and case, either way round")
    func accentsFolded() {
        let zoe = SearchResult(id: UUID(), entityType: .student, title: "Zoë Martin", snippet: "")
        let rene = SearchResult(id: UUID(), entityType: .lesson, title: "Renée's map", snippet: "")
        let index = service(with: [(zoe, "Zoë Martin"), (rene, "Renée map of the world")])

        #expect(index.search(query: "Zoe").map(\.id) == [zoe.id])
        #expect(index.search(query: "ZOË").map(\.id) == [zoe.id])
        #expect(index.search(query: "renee").map(\.id) == [rene.id])
        #expect(SearchIndexService.tokenize("Zoë Ｍartin") == ["zoe", "martin"])
    }
}
