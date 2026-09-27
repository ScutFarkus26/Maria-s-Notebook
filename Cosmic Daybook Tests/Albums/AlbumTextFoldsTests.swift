import Dispatch
import Foundation
import Testing
@testable import CosmicDaybook

/// Search folds an album's page text off the main actor the first time it
/// needs it; the fold used to run on the main actor, inside the first search
/// after every load and every trim. Searches that race while an album folds
/// share that one fold, and every fold is the old eager fold, string for
/// string. `AlbumFoldRecorder` sees each fold and the thread it ran on.
@Suite("Album text folds: off the main actor, once", .serialized)
@MainActor
struct AlbumTextFoldsTests {

    private static let albums: [(id: String, texts: [String])] = (1...3).map { number in
        (id: "Album \(number).pdf", texts: (1...40).map { page in
            "  Page \(page): Élève’s “ﬁrst” STAMP Game – album \(number)\n"
                + String(repeating: "Golden Beads, Café ", count: 12)
        })
    }

    /// What the index build used to fold for each album.
    private static let eager: [[String]] = albums.map { $0.texts.map { $0.folded() } }

    private static func folds(of albums: [(id: String, texts: [String])]) -> [String] {
        albums.map { "fold \($0.id)" }
    }

    @Test("The fold runs off the main thread and gives the old eager fold, page for page")
    func foldsOffTheMainThread() async {
        let folds = AlbumTextFolds()
        let recorder = AlbumFoldRecorder()
        let pages = await AlbumFoldRecorder.$current.withValue(recorder) {
            await folds.pages(for: Self.albums)
        }
        #expect(pages.map(\.folded) == Self.eager)
        #expect(pages.map(\.texts) == Self.albums.map(\.texts))
        #expect(recorder.reached.map(\.name).sorted() == Self.folds(of: Self.albums))
        #expect(recorder.reached.allSatisfy { !$0.onMainThread })
        #expect(folds.kept.count == Self.albums.count)
    }

    @Test("Searches that race while the albums are folding share each album's one fold")
    func racingSearchesFoldOnce() async {
        let folds = AlbumTextFolds()
        let gate = DispatchSemaphore(value: 0)
        // Each fold waits here, on its own thread, until the test lets it go.
        let recorder = AlbumFoldRecorder { _ in _ = gate.wait(timeout: .now() + 30) }
        let first = Task {
            await AlbumFoldRecorder.$current.withValue(recorder) { await folds.pages(for: Self.albums) }
        }
        #expect(await AlbumTestSupport.waitUntil { recorder.reached.count == Self.albums.count })
        let second = Task {
            await AlbumFoldRecorder.$current.withValue(recorder) { await folds.pages(for: Self.albums) }
        }
        #expect(await AlbumTestSupport.waitUntil { folds.foldsJoined == Self.albums.count })
        for _ in Self.albums { gate.signal() }

        let firstPages = await first.value
        let secondPages = await second.value
        #expect(firstPages.map(\.folded) == Self.eager)
        #expect(secondPages == firstPages)
        #expect(recorder.reached.map(\.name).sorted() == Self.folds(of: Self.albums))
    }

    @Test("A fold let go of while it runs still answers its search, and isn't kept")
    func droppedFoldIsNotKept() async {
        let folds = AlbumTextFolds()
        let album = [Self.albums[0]]
        let gate = DispatchSemaphore(value: 0)
        let held = AlbumFoldRecorder { _ in _ = gate.wait(timeout: .now() + 30) }
        let search = Task {
            await AlbumFoldRecorder.$current.withValue(held) { await folds.pages(for: album) }
        }
        #expect(await AlbumTestSupport.waitUntil { held.reached.count == 1 })
        folds.dropAll() // a trim while it folds
        gate.signal()
        #expect(await search.value.map(\.folded) == [Self.eager[0]])
        #expect(folds.kept.isEmpty)

        // The next search folds again, and keeps that one.
        let later = AlbumFoldRecorder()
        let again = await AlbumFoldRecorder.$current.withValue(later) { await folds.pages(for: album) }
        #expect(again.map(\.folded) == [Self.eager[0]])
        #expect(later.reached.count == 1)
        #expect(folds.kept[album[0].id] == Self.eager[0])
    }

    @Test("An album with no page text yet folds nothing and keeps nothing, so its text can arrive")
    func albumWithoutTextKeepsNothing() async {
        let folds = AlbumTextFolds()
        let recorder = AlbumFoldRecorder()
        let unindexed = (id: "Still Indexing.pdf", texts: [String]())
        let pages = await AlbumFoldRecorder.$current.withValue(recorder) { await folds.pages(for: [unindexed]) }
        #expect(pages == [AlbumTextFolds.Pages(texts: [], folded: [])])
        #expect(recorder.reached.isEmpty)
        #expect(folds.kept.isEmpty)

        // Once indexed (after a purge the modification date is unchanged, so
        // nothing drops a fold), the album folds its text.
        let indexed = (id: unindexed.id, texts: Self.albums[0].texts)
        let later = await AlbumFoldRecorder.$current.withValue(recorder) { await folds.pages(for: [indexed]) }
        #expect(later.map(\.folded) == [Self.eager[0]])
        #expect(recorder.reached.map(\.name) == ["fold \(unindexed.id)"])
    }

    @Test("A kept fold serves later searches without folding; an album whose text changed folds again")
    func keptFoldsServeLaterSearches() async {
        let folds = AlbumTextFolds()
        _ = await folds.pages(for: Self.albums)

        let recorder = AlbumFoldRecorder()
        let later = await AlbumFoldRecorder.$current.withValue(recorder) { await folds.pages(for: Self.albums) }
        #expect(recorder.reached.isEmpty)
        #expect(later.map(\.folded) == Self.eager)

        // What a re-index does for an album whose PDF changed.
        folds.drop(albumID: Self.albums[1].id)
        let revised = (id: Self.albums[1].id, texts: ["Revised Page 1: Café"])
        let after = await AlbumFoldRecorder.$current.withValue(recorder) {
            await folds.pages(for: [Self.albums[0], revised, Self.albums[2]])
        }
        #expect(recorder.reached.map(\.name) == ["fold \(Self.albums[1].id)"])
        #expect(after[1] == AlbumTextFolds.Pages(texts: ["Revised Page 1: Café"], folded: ["revised page 1: cafe"]))
        #expect(after[0].folded == Self.eager[0])
        #expect(after[2].folded == Self.eager[2])
    }
}
