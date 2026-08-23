import CoreData
import CoreGraphics
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Album annotation store")
@MainActor
final class AlbumUserDataStoreTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    // MARK: Bookmarks

    @Test("Bookmarking a page toggles it on and off")
    func toggleBookmark() throws {
        let context = try makeContext()
        #expect(!AlbumUserDataStore.isBookmarked(albumID: "Biology.pdf", pageIndex: 4, in: context))

        AlbumUserDataStore.toggleBookmark(albumID: "Biology.pdf", pageIndex: 4,
                                          lessonTitle: "Parts of the Flower", in: context)
        #expect(AlbumUserDataStore.isBookmarked(albumID: "Biology.pdf", pageIndex: 4, in: context))

        AlbumUserDataStore.toggleBookmark(albumID: "Biology.pdf", pageIndex: 4,
                                          lessonTitle: "Parts of the Flower", in: context)
        #expect(!AlbumUserDataStore.isBookmarked(albumID: "Biology.pdf", pageIndex: 4, in: context))
    }

    @Test("Bookmarks are per page, not per album")
    func bookmarksAreScopedToAPage() throws {
        let context = try makeContext()
        AlbumUserDataStore.toggleBookmark(albumID: "Biology.pdf", pageIndex: 4,
                                          lessonTitle: "Flower", in: context)
        #expect(!AlbumUserDataStore.isBookmarked(albumID: "Biology.pdf", pageIndex: 5, in: context))
        #expect(!AlbumUserDataStore.isBookmarked(albumID: "Math.pdf", pageIndex: 4, in: context))
    }

    // MARK: Notes

    @Test("Notes are trimmed, and blank notes are not saved")
    func addNote() throws {
        let context = try makeContext()
        AlbumUserDataStore.addNote(albumID: "Math.pdf", pageIndex: 2, lessonTitle: "Checkerboard",
                                   text: "   ", in: context)
        #expect(AlbumUserDataStore.notes(albumID: "Math.pdf", pageIndex: 2, in: context).isEmpty)

        AlbumUserDataStore.addNote(albumID: "Math.pdf", pageIndex: 2, lessonTitle: "Checkerboard",
                                   text: "  Bring the bead bars.  ", in: context)
        let notes = AlbumUserDataStore.notes(albumID: "Math.pdf", pageIndex: 2, in: context)
        #expect(notes.count == 1)
        #expect(notes.first?.text == "Bring the bead bars.")
    }

    @Test("Note snapshots carry the fields search needs")
    func noteSnapshots() throws {
        let context = try makeContext()
        AlbumUserDataStore.addNote(albumID: "Math.pdf", pageIndex: 7, lessonTitle: "Checkerboard",
                                   text: "Multiplication follow-up", in: context)
        let snapshots = AlbumUserDataStore.noteSnapshots(in: context)
        #expect(snapshots.count == 1)
        let snapshot = try #require(snapshots.first)
        #expect(snapshot.albumID == "Math.pdf")
        #expect(snapshot.pageIndex == 7)
        #expect(snapshot.lessonTitle == "Checkerboard")
        #expect(!snapshot.id.isEmpty)
    }

    // MARK: Recent visits

    @Test("Revisiting a lesson moves it rather than duplicating it")
    func recentVisitsDeduplicateByLesson() throws {
        let context = try makeContext()
        AlbumUserDataStore.recordVisit(albumID: "Bio.pdf", pageIndex: 3,
                                       lessonTitle: "Flower", in: context)
        AlbumUserDataStore.recordVisit(albumID: "Bio.pdf", pageIndex: 9,
                                       lessonTitle: "Flower", in: context)

        let request = CDFetchRequest(CDAlbumRecentVisit.self)
        let visits = context.safeFetch(request)
        #expect(visits.count == 1)
        #expect(visits.first?.pageIndex == 9)
    }

    @Test("Recent visits are capped so the rail stays short")
    func recentVisitsAreCapped() throws {
        let context = try makeContext()
        let overflow = AlbumUserDataStore.recentVisitLimit + 5
        for index in 0..<overflow {
            AlbumUserDataStore.recordVisit(albumID: "Bio.pdf", pageIndex: index,
                                           lessonTitle: "Lesson \(index)", in: context)
        }
        let visits = context.safeFetch(CDFetchRequest(CDAlbumRecentVisit.self))
        #expect(visits.count == AlbumUserDataStore.recentVisitLimit)
    }

    // MARK: Reading position

    @Test("Reading position updates in place")
    func readingPositionUpdates() throws {
        let context = try makeContext()
        AlbumUserDataStore.saveReadingPosition(albumID: "Bio.pdf", pageIndex: 12, in: context)
        AlbumUserDataStore.saveReadingPosition(albumID: "Bio.pdf", pageIndex: 40, in: context)

        #expect(AlbumUserDataStore.readingPosition(albumID: "Bio.pdf", in: context) == 40)
        let rows = context.safeFetch(CDFetchRequest(CDAlbumReadingPosition.self))
        #expect(rows.count == 1)
    }

    @Test("Duplicate reading positions from other devices collapse to one")
    func readingPositionCollapsesCloudKitDuplicates() throws {
        let context = try makeContext()
        // CloudKit can't enforce uniqueness, so two devices can each insert a row.
        for page in [5, 30] {
            let position = CDAlbumReadingPosition(context: context)
            position.albumID = "Bio.pdf"
            position.pageIndex = Int32(page)
        }
        context.safeSave()

        AlbumUserDataStore.saveReadingPosition(albumID: "Bio.pdf", pageIndex: 44, in: context)
        let rows = context.safeFetch(CDFetchRequest(CDAlbumReadingPosition.self))
        #expect(rows.count == 1)
        #expect(AlbumUserDataStore.readingPosition(albumID: "Bio.pdf", in: context) == 44)
    }

    // MARK: Highlights

    @Test("Highlight rectangles survive a store round-trip")
    func highlightRectsRoundTrip() throws {
        let context = try makeContext()
        let rects = [CGRect(x: 10, y: 20, width: 100, height: 12),
                     CGRect(x: 10, y: 34, width: 80, height: 12)]
        AlbumUserDataStore.addHighlight(albumID: "Bio.pdf", pageIndex: 2, lessonTitle: "Flower",
                                        text: "the stamen", rects: rects, in: context)

        let stored = AlbumUserDataStore.highlights(albumID: "Bio.pdf", in: context)
        #expect(stored.count == 1)
        #expect(stored.first?.rects == rects)
        #expect(stored.first?.colorName == "yellow")
    }

    @Test("A highlight with no rectangles is not stored")
    func emptyHighlightIsIgnored() throws {
        let context = try makeContext()
        AlbumUserDataStore.addHighlight(albumID: "Bio.pdf", pageIndex: 2, lessonTitle: "Flower",
                                        text: "nothing selected", rects: [], in: context)
        #expect(AlbumUserDataStore.highlights(albumID: "Bio.pdf", in: context).isEmpty)
    }

    // MARK: Ink

    @Test("Saving ink twice for one page replaces the drawing")
    func inkReplacesPerPage() throws {
        let context = try makeContext()
        AlbumUserDataStore.saveInk(albumID: "Bio.pdf", pageIndex: 3,
                                   drawingData: Data([1, 2, 3]), in: context)
        AlbumUserDataStore.saveInk(albumID: "Bio.pdf", pageIndex: 3,
                                   drawingData: Data([4, 5, 6]), in: context)

        let ink = AlbumUserDataStore.ink(albumID: "Bio.pdf", in: context)
        #expect(ink.count == 1)
        #expect(ink.first?.drawingData == Data([4, 5, 6]))
    }

    @Test("Erasing a page's ink removes its row")
    func erasingInkDeletesRow() throws {
        let context = try makeContext()
        AlbumUserDataStore.saveInk(albumID: "Bio.pdf", pageIndex: 3,
                                   drawingData: Data([1, 2, 3]), in: context)
        AlbumUserDataStore.saveInk(albumID: "Bio.pdf", pageIndex: 3,
                                   drawingData: Data(), in: context)
        #expect(AlbumUserDataStore.ink(albumID: "Bio.pdf", in: context).isEmpty)
    }
}
