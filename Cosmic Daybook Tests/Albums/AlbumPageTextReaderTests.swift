import Foundation
import PDFKit
import Testing
@testable import CosmicDaybook

/// The full-text index reads an album's pages through a fresh opening of the
/// PDF every 50 pages, since PDFKit keeps every page it has read until its
/// document closes (500 dense pages peaked at 444 MB through one document, 81
/// MB this way). The text must be byte for byte what one document gave, every
/// page, in order.
@Suite("Album page text: read through fresh openings of the PDF", .serialized)
@MainActor
struct AlbumPageTextReaderTests {

    /// Text normalizing touches (curly quotes, a ligature) and folding would.
    private static let phrase = "Élève’s “ﬁrst” Stamp Game Division"
    private static let pageCount = 260

    private static func bytes(_ texts: [String]) -> [[UInt8]] {
        texts.map { Array($0.utf8) }
    }

    /// A 260-page album: five stretches of 50 pages and a short one.
    private static func writeLongAlbum(in dir: URL) throws -> URL {
        try AlbumTestSupport.writeAlbum(named: "Long Album.pdf", in: dir, pageCount: pageCount,
                                        outline: AlbumTestSupport.sampleOutline, phrase: phrase)
    }

    @Test("Every page's text is byte for byte what one document read, in page order")
    func textIsUnchanged() throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try Self.writeLongAlbum(in: dir)
        // The extraction before the reopening, verbatim.
        let old = LegacyAlbumIndex.loadOrBuildIndex(url: url, modified: .distantPast, cacheDir: nil).texts
        #expect(old.count == Self.pageCount)

        for stretch in [AlbumPageTextReader.pagesPerOpening, 7, 1, 1_000] {
            let texts = AlbumPageTextReader.pageTexts(url: url, pagesPerOpening: stretch)
            #expect(texts.count == Self.pageCount)
            #expect(Self.bytes(texts) == Self.bytes(old))
        }
        // In page order: each page's own line.
        let texts = AlbumPageTextReader.pageTexts(url: url)
        #expect(texts.indices.allSatisfy { texts[$0].contains("Page \($0 + 1): ") })
        // And through the index's own entry point.
        #expect(Self.bytes(AlbumLibrary.loadOrBuildIndex(url: url, modified: .distantPast, cacheDir: nil))
                == Self.bytes(old))
    }

    @Test("A stretch whose reopening fails, or finds other pages, is read from the first opening")
    func reopeningFallsBack() throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try Self.writeLongAlbum(in: dir)
        let other = try AlbumTestSupport.writeAlbum(named: "Short Album.pdf", in: dir,
                                                    outline: AlbumTestSupport.sampleOutline)
        let old = LegacyAlbumIndex.loadOrBuildIndex(url: url, modified: .distantPast, cacheDir: nil).texts

        var openings = 0
        let failing = AlbumPageTextReader.pageTexts(url: url) { fileURL in
            openings += 1
            // Only the first opening succeeds; after it, every other one fails
            // or opens a different, four-page PDF.
            switch openings {
            case 1: return PDFDocument(url: fileURL)
            case _ where openings.isMultiple(of: 2): return nil
            default: return PDFDocument(url: other)
            }
        }
        #expect(openings == 1 + 6)
        #expect(Self.bytes(failing) == Self.bytes(old))

        #expect(AlbumPageTextReader.pageTexts(url: url) { _ in nil }.isEmpty)
    }
}
