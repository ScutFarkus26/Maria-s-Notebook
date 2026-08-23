import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Album search engine")
struct AlbumSearchEngineTests {

    // MARK: Fixtures

    /// A two-album corpus: one page mentions "borrowing", the other doesn't.
    private func makeCorpus() -> AlbumSearchCorpus {
        let mathPages = [
            "Title page for the mathematics album.",
            "The Stamp Game presents addition and subtraction with coloured tiles.",
            "In subtraction with exchange the child changes a ten for ten units."
        ]
        let bioPages = [
            "Title page for the biology album.",
            "Parts of the Flower: the stamen, pistil, and petals are named in turn."
        ]
        let math = AlbumSearchCorpus.AlbumData(
            id: "Math.pdf",
            title: "Math",
            subject: .math,
            lessons: [
                AlbumLessonRef(title: "Stamp Game", pageIndex: 1, depth: 0),
                AlbumLessonRef(title: "Subtraction with Exchange", pageIndex: 2, depth: 0)
            ],
            texts: mathPages,
            folded: mathPages.map { AlbumLibrary.fold(AlbumLibrary.normalize($0)) }
        )
        let biology = AlbumSearchCorpus.AlbumData(
            id: "Biology.pdf",
            title: "Biology",
            subject: .biology,
            lessons: [AlbumLessonRef(title: "Parts of the Flower", pageIndex: 1, depth: 0)],
            texts: bioPages,
            folded: bioPages.map { AlbumLibrary.fold(AlbumLibrary.normalize($0)) }
        )
        return AlbumSearchCorpus(albums: [math, biology])
    }

    // MARK: Tokens

    @Test("Tokenizing splits on punctuation and folds case")
    func tokens() {
        #expect(AlbumSearchEngine.tokens(for: "Parts of the Flower!") == ["parts", "of", "the", "flower"])
        #expect(AlbumSearchEngine.tokens(for: "   ").isEmpty)
    }

    // MARK: Search

    @Test("An empty query returns no results")
    func emptyQuery() {
        let results = AlbumSearchEngine.search(query: "  ", corpus: makeCorpus(),
                                               notes: [], albumFilter: nil)
        #expect(results.isEmpty)
    }

    @Test("Lesson titles match ahead of page content")
    func lessonTitleHits() {
        let results = AlbumSearchEngine.search(query: "stamp game", corpus: makeCorpus(),
                                               notes: [], albumFilter: nil)
        #expect(results.lessonHits.contains { $0.lessonTitle == "Stamp Game" })
    }

    @Test("Page text matches carry the lesson they sit under")
    func pageHitsCarryLesson() {
        let results = AlbumSearchEngine.search(query: "stamen", corpus: makeCorpus(),
                                               notes: [], albumFilter: nil)
        let hit = try? #require(results.pageGroups.first?.hits.first)
        #expect(hit?.albumID == "Biology.pdf")
        #expect(hit?.lessonTitle == "Parts of the Flower")
    }

    @Test("The album filter keeps other albums out of the results")
    func albumFilter() {
        let results = AlbumSearchEngine.search(query: "album", corpus: makeCorpus(),
                                               notes: [], albumFilter: "Biology.pdf")
        #expect(results.pageGroups.allSatisfy { group in
            group.hits.allSatisfy { $0.albumID == "Biology.pdf" }
        })
    }

    @Test("The guide's own notes are searched alongside the albums")
    func noteHits() {
        let note = AlbumNoteSnapshot(id: "n1", albumID: "Math.pdf", pageIndex: 2,
                                     lessonTitle: "Subtraction with Exchange",
                                     text: "Sarah needed the golden beads here.")
        let results = AlbumSearchEngine.search(query: "golden beads", corpus: makeCorpus(),
                                               notes: [note], albumFilter: nil)
        #expect(results.noteHits.count == 1)
        #expect(results.noteHits.first?.albumID == "Math.pdf")
    }

    // MARK: Snippets

    @Test("Snippets window around the match and ellipsize the edges")
    func snippet() {
        let text = String(repeating: "padding words ", count: 30) + "stamen "
            + String(repeating: "more words ", count: 30)
        let snippet = AlbumSearchEngine.snippet(in: text, query: "stamen", terms: ["stamen"])
        #expect(snippet.contains("stamen"))
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
    }

    // MARK: Retrieval for Ask

    @Test("Retrieval ranks the page that answers the question first")
    func retrieveRanksBestPage() {
        let picks = AlbumSearchEngine.retrieve(question: "How do I present subtraction with exchange?",
                                               corpus: makeCorpus(), limit: 5)
        let first = try? #require(picks.first)
        #expect(first?.album.id == "Math.pdf")
        #expect(first?.pageIndex == 2)
    }

    @Test("Retrieval keeps at most two pages per lesson so sources stay varied")
    func retrieveLimitsPagesPerLesson() {
        let pages = (0..<6).map { _ in "subtraction exchange units tens" }
        let album = AlbumSearchCorpus.AlbumData(
            id: "Math.pdf", title: "Math", subject: .math,
            lessons: [AlbumLessonRef(title: "Subtraction", pageIndex: 0, depth: 0)],
            texts: pages,
            folded: pages.map { AlbumLibrary.fold(AlbumLibrary.normalize($0)) }
        )
        let picks = AlbumSearchEngine.retrieve(question: "subtraction",
                                               corpus: AlbumSearchCorpus(albums: [album]),
                                               limit: 6)
        #expect(picks.count <= 2)
    }

    @Test("A semantic boost surfaces a page with no keyword overlap")
    func retrieveUsesSemanticBoost() {
        let corpus = makeCorpus()
        // "borrowing" appears nowhere in the text; the boost stands in for the
        // semantic index scoring the Subtraction lesson highly.
        let withoutBoost = AlbumSearchEngine.retrieve(question: "borrowing",
                                                      corpus: corpus, limit: 5)
        #expect(withoutBoost.isEmpty)

        let boosted = AlbumSearchEngine.retrieve(question: "borrowing", corpus: corpus, limit: 5,
                                                 boost: ["Math.pdf": [0, 0.9]])
        #expect(boosted.contains { $0.album.id == "Math.pdf" && $0.pageIndex == 2 })
    }
}
