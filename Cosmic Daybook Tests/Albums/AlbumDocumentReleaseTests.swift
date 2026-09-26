import CoreData
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import CosmicDaybook

/// An album no longer keeps its PDF open for the life of the app. It reads its
/// outline, lessons, page count and fingerprint at load and closes the file; a
/// reader, an export or a match thumbnail opens it again, and a memory trim
/// (`releaseMemory`, including the idle trim) lets it go. A PDF a reader is
/// still showing survives the trim as the same document.
@Suite("Album documents: released by a trim, reopened on use")
@MainActor
struct AlbumDocumentReleaseTests {

    private struct FindHit: Equatable {
        let pageIndex: Int
        let text: String?
        let bounds: CGRect
    }

    private struct AnnotationMark: Equatable {
        let pageIndex: Int
        let type: String?
        let bounds: CGRect
        let color: [CGFloat]
    }

    private func findHits(_ query: String, in document: PDFDocument) -> [FindHit] {
        // The reader's options: `AlbumPDFViewerProxy.findMatches` and the
        // search-highlight jump both search this way.
        document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive]).flatMap { selection in
            selection.pages.map { page in
                FindHit(pageIndex: document.index(for: page), text: selection.string,
                        bounds: selection.bounds(for: page))
            }
        }
    }

    private func marks(in document: PDFDocument) -> [AnnotationMark] {
        (0..<document.pageCount).flatMap { index in
            (document.page(at: index)?.annotations ?? []).map { annotation in
                AnnotationMark(pageIndex: index, type: annotation.type, bounds: annotation.bounds,
                               color: annotation.color.cgColor.components ?? [])
            }
        }
    }

    private func makeHighlights(for album: Album,
                                in context: NSManagedObjectContext) -> [CDAlbumHighlight] {
        AlbumUserDataStore.addHighlight(albumID: album.id, pageIndex: 1, lessonTitle: "Subtraction",
                                        text: "stamp game",
                                        rects: [CGRect(x: 60, y: 396, width: 180, height: 24),
                                                CGRect(x: 60, y: 480, width: 120, height: 20)],
                                        in: context)
        AlbumUserDataStore.addHighlight(albumID: album.id, pageIndex: 3, lessonTitle: "Sharing",
                                        text: "skittles", colorName: "green",
                                        rects: [CGRect(x: 300, y: 396, width: 90, height: 24)],
                                        in: context)
        return AlbumUserDataStore.highlights(albumID: album.id, in: context)
            .sorted { $0.pageIndex < $1.pageIndex }
    }

    @Test("Nine albums opened by readers hold no PDF once a trim lets them go")
    func trimClosesEveryDocument() throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let albums: [Album] = try (1...9).map { (number: Int) throws -> Album in
            let url = try AlbumTestSupport.writeAlbum(named: "Album \(number).pdf", in: dir,
                                                      outline: AlbumTestSupport.sampleOutline)
            return try #require(Album(url: url))
        }

        // A reader, an export or a match thumbnail opens each one; Find fills
        // in every page's text on the way.
        let opened: [AlbumTestWeakBox<PDFDocument>] = autoreleasepool {
            albums.map { (album: Album) -> AlbumTestWeakBox<PDFDocument> in
                let document = album.document
                _ = document?.findString("stamp game", withOptions: [.caseInsensitive])
                return AlbumTestWeakBox(document)
            }
        }
        #expect(opened.count { $0.object != nil } == 9)
        // Opened again before a trim, it is the same document, not a new one.
        for (album, box) in zip(albums, opened) {
            #expect(album.document === box.object)
        }

        // Every reader closed; the trim (`releaseMemory`) releases each album.
        autoreleasepool {
            for album in albums { album.releaseDocument() }
        }
        #expect(opened.count { $0.object != nil } == 0)
    }

    /// What a reader shows of an album's document: Find hits and highlights.
    private struct ReaderView: Equatable {
        let findHits: [FindHit]
        let marks: [AnnotationMark]
    }

    /// Opens the album's document as a reader does, applies the highlights and
    /// records what it shows, watching the document through `watch`.
    private func read(_ album: Album, highlights: [CDAlbumHighlight],
                      watch: AlbumTestWeakBox<PDFDocument>) throws -> ReaderView {
        try autoreleasepool { () throws -> ReaderView in
            let document = try #require(album.document)
            watch.object = document
            album.applyHighlights(highlights)
            return ReaderView(findHits: findHits("stamp game", in: document), marks: marks(in: document))
        }
    }

    private static let lessonTitles: [String] = [
        "Simple Operations", "Subtraction", "Stamp Game Division", "Sharing Among the Skittles"
    ]
    private static let lessonPages: [Int] = [0, 1, 2, 3]
    private static let topLevelTitles: [String] = [
        "Simple Operations", "Stamp Game Division", "Sharing Among the Skittles"
    ]

    @Test("Outline, lessons and fingerprint are what the open document used to give")
    func valuesMatchTheDocument() throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AlbumTestSupport.writeAlbum(named: "Math Album.pdf", in: dir,
                                                  outline: AlbumTestSupport.sampleOutline)
        let album = try #require(Album(url: url))
        let reference = try #require(PDFDocument(url: url))
        let firstPageText: String = reference.page(at: 0)?.string ?? ""
        let fingerprint = AlbumIdentityRepair.fingerprint(
            pageCount: reference.pageCount, lessonTitles: Self.lessonTitles, firstPageText: firstPageText)

        #expect(album.pageCount == reference.pageCount)
        #expect(album.lessons.map(\.title) == Self.lessonTitles)
        #expect(album.lessons.map(\.pageIndex) == Self.lessonPages)
        #expect(album.outline.map(\.title) == Self.topLevelTitles)
        #expect(album.outline.first?.children?.map(\.title) == ["Subtraction"])
        #expect(album.fingerprint == fingerprint)
    }

    @Test("Find and highlights are the same after a release and reopen")
    func reopenedDocumentBehavesTheSame() throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AlbumTestSupport.writeAlbum(named: "Math Album.pdf", in: dir,
                                                  outline: AlbumTestSupport.sampleOutline)
        let album = try #require(Album(url: url))
        let context = try CoreDataTestHelpers.makeContext()
        let highlights = makeHighlights(for: album, in: context)

        let first = AlbumTestWeakBox<PDFDocument>(nil)
        let before = try read(album, highlights: highlights, watch: first)
        #expect(before.findHits.count == album.pageCount)
        #expect(before.marks.count == 3)

        autoreleasepool { album.releaseDocument() }
        #expect(first.object == nil)

        // The next reader reopens the file and applies the highlights again.
        let second = AlbumTestWeakBox<PDFDocument>(nil)
        let after = try read(album, highlights: highlights, watch: second)
        #expect(second.object != nil)
        #expect(after == before)
        #expect(album.outline.map(\.title) == Self.topLevelTitles)
    }

    @Test("A trim while a reader shows the album keeps that document and its highlights")
    func trimKeepsTheShownDocument() throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AlbumTestSupport.writeAlbum(named: "Biology Album.pdf", in: dir,
                                                  outline: AlbumTestSupport.sampleOutline)
        let album = try #require(Album(url: url))
        let context = try CoreDataTestHelpers.makeContext()
        let highlights = makeHighlights(for: album, in: context)

        // The reader's PDFView holds this document for as long as it shows it.
        let shown = try #require(album.document)
        album.applyHighlights(highlights)
        let applied = marks(in: shown)

        autoreleasepool { album.releaseDocument() }
        // No new document under the reader: the next use gets the same one back.
        #expect(album.document === shown)
        // The reader re-applies highlights on the next change; they replace
        // the ones already drawn rather than doubling them.
        album.applyHighlights(highlights)
        #expect(marks(in: shown) == applied)
        album.applyHighlights([])
        #expect(marks(in: shown).isEmpty)
    }
}
