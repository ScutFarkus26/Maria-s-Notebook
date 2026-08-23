import CoreData
import CoreGraphics
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Albums app data import")
@MainActor
final class AlbumsDataImporterTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func writeFixture(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("albums-import-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The shape the standalone app's 1.0 store used: no reading positions,
    /// no highlights, no ink.
    private let legacyPayload = """
        {
          "bookmarks": [
            {"albumID": "Bio.pdf", "pageIndex": 4, "lessonTitle": "Flower", "created": 780000000}
          ],
          "notes": [
            {"albumID": "Bio.pdf", "pageIndex": 4, "lessonTitle": "Flower",
             "text": "Bring real lilies", "created": 780000000, "modified": 780000100}
          ],
          "recents": [
            {"albumID": "Bio.pdf", "pageIndex": 4, "lessonTitle": "Flower", "date": 780000000}
          ]
        }
        """

    @Test("A 1.0 export imports bookmarks, notes, and recents")
    func importsLegacyShape() throws {
        let context = try makeContext()
        let url = try writeFixture(legacyPayload)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = AlbumsDataImporter.importData(from: url, into: context)
        #expect(summary.contains("1 bookmarks"))
        #expect(summary.contains("1 notes"))
        #expect(summary.contains("1 recents"))

        #expect(AlbumUserDataStore.isBookmarked(albumID: "Bio.pdf", pageIndex: 4, in: context))
        let notes = AlbumUserDataStore.notes(albumID: "Bio.pdf", pageIndex: 4, in: context)
        #expect(notes.first?.text == "Bring real lilies")
    }

    @Test("Re-importing the same file adds nothing")
    func importIsIdempotent() throws {
        let context = try makeContext()
        let url = try writeFixture(legacyPayload)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = AlbumsDataImporter.importData(from: url, into: context)
        let second = AlbumsDataImporter.importData(from: url, into: context)

        #expect(second.contains("Nothing new"))
        #expect(context.safeFetch(CDFetchRequest(CDAlbumBookmark.self)).count == 1)
        #expect(context.safeFetch(CDFetchRequest(CDAlbumPageNote.self)).count == 1)
    }

    @Test("A full export also imports positions, highlights, and ink")
    func importsFullShape() throws {
        let context = try makeContext()
        let url = try writeFixture("""
            {
              "bookmarks": [],
              "notes": [],
              "recents": [],
              "readingPositions": [
                {"albumID": "Math.pdf", "pageIndex": 31, "updated": 780000000}
              ],
              "highlights": [
                {"albumID": "Math.pdf", "pageIndex": 12, "lessonTitle": "Checkerboard",
                 "text": "lay out the bead bars", "colorName": "green",
                 "rects": [[10, 20, 100, 12]], "created": 780000000}
              ],
              "ink": [
                {"albumID": "Math.pdf", "pageIndex": 12, "drawingData": "AQID",
                 "modified": 780000000}
              ]
            }
            """)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = AlbumsDataImporter.importData(from: url, into: context)
        #expect(summary.contains("1 reading positions"))
        #expect(summary.contains("1 highlights"))
        #expect(summary.contains("1 ink drawings"))

        #expect(AlbumUserDataStore.readingPosition(albumID: "Math.pdf", in: context) == 31)

        let highlight = try #require(
            AlbumUserDataStore.highlights(albumID: "Math.pdf", in: context).first
        )
        #expect(highlight.colorName == "green")
        #expect(highlight.rects == [CGRect(x: 10, y: 20, width: 100, height: 12)])

        let ink = try #require(AlbumUserDataStore.ink(albumID: "Math.pdf", in: context).first)
        #expect(ink.drawingData == Data([1, 2, 3]))
    }

    @Test("A file that isn't an Albums export is reported, not imported")
    func rejectsUnrelatedJSON() throws {
        let context = try makeContext()
        let url = try writeFixture("[1, 2, 3]")
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = AlbumsDataImporter.importData(from: url, into: context)
        #expect(summary.contains("doesn't look like an Albums export"))
        #expect(context.safeFetch(CDFetchRequest(CDAlbumBookmark.self)).isEmpty)
    }
}
