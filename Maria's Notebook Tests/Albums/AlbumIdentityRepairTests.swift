import CoreData
import CoreGraphics
import Foundation
import Testing
@testable import Maria_s_Notebook

/// Renaming an album PDF used to orphan every mark the guide had made in it.
/// These cover the fingerprint that recognises a renamed album and the remap
/// that carries the guide's work across.
@Suite("Album identity repair")
@MainActor
final class AlbumIdentityRepairTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    // MARK: Fingerprinting

    @Test("The same album content fingerprints the same way")
    func fingerprintIsStable() {
        let first = AlbumIdentityRepair.fingerprint(
            pageCount: 120,
            lessonTitles: ["Parts of the Flower", "The Seed"],
            firstPageText: "Biology Album\nUpper Elementary")
        let second = AlbumIdentityRepair.fingerprint(
            pageCount: 120,
            lessonTitles: ["Parts of the Flower", "The Seed"],
            firstPageText: "Biology Album\nUpper Elementary")
        #expect(first == second)
    }

    @Test("Whitespace differences in the first page don't change the fingerprint")
    func fingerprintIgnoresWhitespaceRuns() {
        let tight = AlbumIdentityRepair.fingerprint(
            pageCount: 10, lessonTitles: ["A"], firstPageText: "Biology Album")
        let loose = AlbumIdentityRepair.fingerprint(
            pageCount: 10, lessonTitles: ["A"], firstPageText: "  Biology   \n\n Album  ")
        #expect(tight == loose)
    }

    @Test("A genuinely different album fingerprints differently")
    func fingerprintDistinguishesAlbums() {
        let biology = AlbumIdentityRepair.fingerprint(
            pageCount: 120, lessonTitles: ["Parts of the Flower"], firstPageText: "Biology")
        let differentPageCount = AlbumIdentityRepair.fingerprint(
            pageCount: 121, lessonTitles: ["Parts of the Flower"], firstPageText: "Biology")
        let differentOutline = AlbumIdentityRepair.fingerprint(
            pageCount: 120, lessonTitles: ["The Checkerboard"], firstPageText: "Biology")
        let differentText = AlbumIdentityRepair.fingerprint(
            pageCount: 120, lessonTitles: ["Parts of the Flower"], firstPageText: "Math")

        #expect(biology != differentPageCount)
        #expect(biology != differentOutline)
        #expect(biology != differentText)
    }

    // MARK: Remapping

    @Test("Renaming an album carries every kind of annotation across")
    func remapMovesAllAnnotationTypes() throws {
        let context = try makeContext()
        let old = "Biology Album.pdf"
        let new = "Biology.pdf"

        let bookmark = CDAlbumBookmark(context: context)
        bookmark.albumID = old
        bookmark.pageIndex = 4

        let note = CDAlbumPageNote(context: context)
        note.albumID = old
        note.pageIndex = 4
        note.text = "Bring the real flowers"

        let visit = CDAlbumRecentVisit(context: context)
        visit.albumID = old
        visit.lessonTitle = "Parts of the Flower"

        let position = CDAlbumReadingPosition(context: context)
        position.albumID = old
        position.pageIndex = 42

        let highlight = CDAlbumHighlight(context: context)
        highlight.albumID = old
        highlight.pageIndex = 4
        highlight.rects = [CGRect(x: 0, y: 0, width: 10, height: 10)]

        let ink = CDAlbumPageInk(context: context)
        ink.albumID = old
        ink.pageIndex = 4
        ink.drawingData = Data([0x01, 0x02])

        context.safeSave()

        AlbumIdentityRepair.remap(from: old, to: new, in: context)

        #expect(bookmark.albumID == new)
        #expect(note.albumID == new)
        #expect(visit.albumID == new)
        #expect(position.albumID == new)
        #expect(highlight.albumID == new)
        #expect(ink.albumID == new)
    }

    @Test("Lessons linked into the album travel with it")
    func remapMovesLessonLinks() throws {
        let context = try makeContext()
        let lesson = CDLesson(context: context)
        lesson.name = "Parts of the Flower"
        lesson.albumLink = AlbumLink(albumID: "Biology Album.pdf", pageIndex: 12,
                                     lessonTitle: "Parts of the Flower")
        context.safeSave()

        AlbumIdentityRepair.remap(from: "Biology Album.pdf", to: "Biology.pdf", in: context)

        #expect(lesson.albumLink?.albumID == "Biology.pdf")
        // The page and outline title are untouched — only the file changed name.
        #expect(lesson.albumLink?.pageIndex == 12)
        #expect(lesson.albumLink?.lessonTitle == "Parts of the Flower")
    }

    @Test("Annotations on other albums are left alone")
    func remapLeavesOtherAlbumsAlone() throws {
        let context = try makeContext()
        let other = CDAlbumBookmark(context: context)
        other.albumID = "Math Album.pdf"
        other.pageIndex = 7
        context.safeSave()

        AlbumIdentityRepair.remap(from: "Biology Album.pdf", to: "Biology.pdf", in: context)

        #expect(other.albumID == "Math Album.pdf")
    }
}
