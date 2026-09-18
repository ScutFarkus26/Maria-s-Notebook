// Reads and writes for the guide's album annotations. Each mutation saves
// immediately: bookmarking a page or drawing on it should survive the app
// being killed moments later, and these are small single-row writes.

import CoreData
import CoreGraphics
import Foundation

enum AlbumUserDataStore {

    // MARK: Bookmarks

    static func bookmark(albumID: String, pageIndex: Int,
                         in context: NSManagedObjectContext) -> CDAlbumBookmark? {
        let request = CDFetchRequest(CDAlbumBookmark.self)
        request.predicate = NSPredicate(format: "albumID == %@ AND pageIndex == %d",
                                        albumID, Int32(pageIndex))
        return context.safeFetchFirst(request)
    }

    static func isBookmarked(albumID: String, pageIndex: Int,
                             in context: NSManagedObjectContext) -> Bool {
        bookmark(albumID: albumID, pageIndex: pageIndex, in: context) != nil
    }

    static func toggleBookmark(albumID: String, pageIndex: Int, lessonTitle: String,
                               in context: NSManagedObjectContext) {
        if let existing = bookmark(albumID: albumID, pageIndex: pageIndex, in: context) {
            context.delete(existing)
        } else {
            let mark = CDAlbumBookmark(context: context)
            mark.albumID = albumID
            mark.pageIndex = Int32(pageIndex)
            mark.lessonTitle = lessonTitle
        }
        context.safeSave()
    }

    // MARK: Notes

    static func addNote(albumID: String, pageIndex: Int, lessonTitle: String, text: String,
                        in context: NSManagedObjectContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = CDAlbumPageNote(context: context)
        note.albumID = albumID
        note.pageIndex = Int32(pageIndex)
        note.lessonTitle = lessonTitle
        note.text = trimmed
        context.safeSave()
    }

    static func notes(albumID: String, pageIndex: Int,
                      in context: NSManagedObjectContext) -> [CDAlbumPageNote] {
        let request = CDFetchRequest(CDAlbumPageNote.self)
        request.predicate = NSPredicate(format: "albumID == %@ AND pageIndex == %d",
                                        albumID, Int32(pageIndex))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDAlbumPageNote.createdAt,
                                                    ascending: true)]
        return context.safeFetch(request)
    }

    /// Sendable copies for the background search pass.
    static func noteSnapshots(in context: NSManagedObjectContext) -> [AlbumNoteSnapshot] {
        let request = CDFetchRequest(CDAlbumPageNote.self)
        return context.safeFetch(request).map { note in
            AlbumNoteSnapshot(
                id: note.id?.uuidString ?? note.objectID.uriRepresentation().absoluteString,
                albumID: note.albumID,
                pageIndex: Int(note.pageIndex),
                lessonTitle: note.lessonTitle,
                text: note.text
            )
        }
    }

    // MARK: Recent visits

    static func recordVisit(albumID: String, pageIndex: Int, lessonTitle: String,
                            in context: NSManagedObjectContext) {
        // One entry per lesson: revisiting a lesson moves it to the top
        // rather than stacking up duplicates.
        let stale = CDFetchRequest(CDAlbumRecentVisit.self)
        stale.predicate = NSPredicate(format: "albumID == %@ AND lessonTitle == %@",
                                      albumID, lessonTitle)
        for visit in context.safeFetch(stale) {
            context.delete(visit)
        }

        let visit = CDAlbumRecentVisit(context: context)
        visit.albumID = albumID
        visit.pageIndex = Int32(pageIndex)
        visit.lessonTitle = lessonTitle

        // Trim in Swift rather than with fetchOffset: a fetch that includes
        // pending changes — and the visit above is still pending — ignores the
        // offset, which would sweep up every row instead of the overflow.
        let all = CDFetchRequest(CDAlbumRecentVisit.self)
        all.sortDescriptors = [NSSortDescriptor(keyPath: \CDAlbumRecentVisit.visitedAt,
                                                ascending: false)]
        for overflow in context.safeFetch(all).dropFirst(Self.recentVisitLimit) {
            context.delete(overflow)
        }
        context.safeSave()
    }

    /// How many recent lessons the library's "Pick Up Where You Left Off" rail keeps.
    static let recentVisitLimit = 30

    // MARK: Reading position

    static func saveReadingPosition(albumID: String, pageIndex: Int,
                                    in context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDAlbumReadingPosition.self)
        request.predicate = NSPredicate(format: "albumID == %@", albumID)
        let existing = context.safeFetch(request)
        if let first = existing.first {
            first.pageIndex = Int32(pageIndex)
            first.modifiedAt = Date()
            // CloudKit can't enforce uniqueness; collapse any duplicates that
            // arrived from other devices.
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
        } else {
            let position = CDAlbumReadingPosition(context: context)
            position.albumID = albumID
            position.pageIndex = Int32(pageIndex)
        }
        context.safeSave()
    }

    static func readingPosition(albumID: String, in context: NSManagedObjectContext) -> Int? {
        let request = CDFetchRequest(CDAlbumReadingPosition.self)
        request.predicate = NSPredicate(format: "albumID == %@", albumID)
        return context.safeFetch(request).map { Int($0.pageIndex) }.max()
    }

    // MARK: Highlights

    static func highlights(albumID: String,
                           in context: NSManagedObjectContext) -> [CDAlbumHighlight] {
        let request = CDFetchRequest(CDAlbumHighlight.self)
        request.predicate = NSPredicate(format: "albumID == %@", albumID)
        return context.safeFetch(request)
    }

    static func addHighlight(albumID: String, pageIndex: Int, lessonTitle: String,
                             text: String, colorName: String = "yellow", rects: [CGRect],
                             in context: NSManagedObjectContext) {
        guard !rects.isEmpty else { return }
        let highlight = CDAlbumHighlight(context: context)
        highlight.albumID = albumID
        highlight.pageIndex = Int32(pageIndex)
        highlight.lessonTitle = lessonTitle
        highlight.text = text
        highlight.colorName = colorName
        highlight.rects = rects
        context.safeSave()
    }

    static func delete(_ highlight: CDAlbumHighlight, in context: NSManagedObjectContext) {
        context.delete(highlight)
        context.safeSave()
    }

    // MARK: Ink

    static func ink(albumID: String, in context: NSManagedObjectContext) -> [CDAlbumPageInk] {
        let request = CDFetchRequest(CDAlbumPageInk.self)
        request.predicate = NSPredicate(format: "albumID == %@", albumID)
        return context.safeFetch(request)
    }

    static func saveInk(albumID: String, pageIndex: Int, drawingData: Data,
                        in context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDAlbumPageInk.self)
        request.predicate = NSPredicate(format: "albumID == %@ AND pageIndex == %d",
                                        albumID, Int32(pageIndex))
        let existing = context.safeFetch(request)
        defer { context.safeSave() }

        // An erased page drops its row rather than storing an empty drawing.
        if drawingData.isEmpty {
            for item in existing { context.delete(item) }
            return
        }
        if let first = existing.first {
            first.drawingData = drawingData
            first.modifiedAt = Date()
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
        } else {
            let ink = CDAlbumPageInk(context: context)
            ink.albumID = albumID
            ink.pageIndex = Int32(pageIndex)
            ink.drawingData = drawingData
        }
    }
}
