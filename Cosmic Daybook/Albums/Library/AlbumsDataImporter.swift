// One-time import of annotations from the standalone Albums app.
//
// The notebook is sandboxed and can't read another app's container, so the
// data arrives as a JSON file the guide picks (Scripts/export_albums_user_data.sh
// produces it). The field names match the standalone app's own export shape,
// and every section is optional so both the 1.0 file (bookmarks/notes/recents)
// and a full export decode.
//
// Re-importing the same file is safe: records already present — matched on
// album, page, and text — are skipped rather than duplicated.

import CoreData
import Foundation

enum AlbumsDataImporter {

    // MARK: Payload

    private struct ImportedBookmark: Decodable {
        var albumID: String
        var pageIndex: Int
        var lessonTitle: String
        var created: Date?
    }

    private struct ImportedNote: Decodable {
        var albumID: String
        var pageIndex: Int
        var lessonTitle: String
        var text: String
        var created: Date?
        var modified: Date?
    }

    private struct ImportedVisit: Decodable {
        var albumID: String
        var pageIndex: Int
        var lessonTitle: String
        var date: Date?
    }

    private struct ImportedPosition: Decodable {
        var albumID: String
        var pageIndex: Int
        var updated: Date?
    }

    private struct ImportedHighlight: Decodable {
        var albumID: String
        var pageIndex: Int
        var lessonTitle: String
        var text: String
        var colorName: String?
        /// [[x, y, width, height]] in page space.
        var rects: [[Double]]?
        var created: Date?
    }

    private struct ImportedInk: Decodable {
        var albumID: String
        var pageIndex: Int
        /// Base64 PencilKit drawing data.
        var drawingData: Data
        var modified: Date?
    }

    private struct Payload: Decodable {
        // Optional rather than defaulted: a synthesized decoder throws on a
        // missing key even when the property has a default, and the 1.0 export
        // carries only bookmarks, notes, and recents.
        var bookmarks: [ImportedBookmark]?
        var notes: [ImportedNote]?
        var recents: [ImportedVisit]?
        var readingPositions: [ImportedPosition]?
        var highlights: [ImportedHighlight]?
        var ink: [ImportedInk]?
    }

    private static let notAnExportMessage =
        "That doesn't look like an Albums export. Expected a JSON file with "
        + "bookmarks, notes, and recents."

    // MARK: Import

    /// Reads the export at `url` and inserts anything not already present.
    /// Returns a short summary for the confirmation alert.
    static func importData(from url: URL, into context: NSManagedObjectContext) -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            return "Couldn't read that file."
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Self.notAnExportMessage
        }

        // A file with none of the known sections is some other JSON entirely.
        guard payload.bookmarks != nil || payload.notes != nil || payload.recents != nil
                || payload.readingPositions != nil || payload.highlights != nil
                || payload.ink != nil else {
            return Self.notAnExportMessage
        }

        var counts: [String: Int] = [:]
        counts["bookmarks"] = importBookmarks(payload.bookmarks ?? [], into: context)
        counts["notes"] = importNotes(payload.notes ?? [], into: context)
        counts["recents"] = importVisits(payload.recents ?? [], into: context)
        counts["reading positions"] = importPositions(payload.readingPositions ?? [], into: context)
        counts["highlights"] = importHighlights(payload.highlights ?? [], into: context)
        counts["ink drawings"] = importInk(payload.ink ?? [], into: context)
        context.safeSave()

        let added = counts.filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { "\($0.value) \($0.key)" }
        guard !added.isEmpty else {
            return "Nothing new to import — everything in that file is already here."
        }
        return "Imported " + added.joined(separator: ", ") + "."
    }

    // MARK: Per-type import

    private static func importBookmarks(_ items: [ImportedBookmark],
                                        into context: NSManagedObjectContext) -> Int {
        var added = 0
        for item in items {
            let request = CDFetchRequest(CDAlbumBookmark.self)
            request.predicate = NSPredicate(format: "albumID == %@ AND pageIndex == %d",
                                            item.albumID, Int32(item.pageIndex))
            guard context.safeFetchFirst(request) == nil else { continue }
            let mark = CDAlbumBookmark(context: context)
            mark.albumID = item.albumID
            mark.pageIndex = Int32(item.pageIndex)
            mark.lessonTitle = item.lessonTitle
            mark.createdAt = item.created ?? Date()
            added += 1
        }
        return added
    }

    private static func importNotes(_ items: [ImportedNote],
                                    into context: NSManagedObjectContext) -> Int {
        var added = 0
        for item in items {
            let request = CDFetchRequest(CDAlbumPageNote.self)
            request.predicate = NSPredicate(
                format: "albumID == %@ AND pageIndex == %d AND text == %@",
                item.albumID, Int32(item.pageIndex), item.text
            )
            guard context.safeFetchFirst(request) == nil else { continue }
            let note = CDAlbumPageNote(context: context)
            note.albumID = item.albumID
            note.pageIndex = Int32(item.pageIndex)
            note.lessonTitle = item.lessonTitle
            note.text = item.text
            note.createdAt = item.created ?? Date()
            note.modifiedAt = item.modified ?? item.created ?? Date()
            added += 1
        }
        return added
    }

    private static func importVisits(_ items: [ImportedVisit],
                                     into context: NSManagedObjectContext) -> Int {
        var added = 0
        for item in items {
            let request = CDFetchRequest(CDAlbumRecentVisit.self)
            request.predicate = NSPredicate(format: "albumID == %@ AND lessonTitle == %@",
                                            item.albumID, item.lessonTitle)
            guard context.safeFetchFirst(request) == nil else { continue }
            let visit = CDAlbumRecentVisit(context: context)
            visit.albumID = item.albumID
            visit.pageIndex = Int32(item.pageIndex)
            visit.lessonTitle = item.lessonTitle
            visit.visitedAt = item.date ?? Date()
            added += 1
        }
        return added
    }

    private static func importPositions(_ items: [ImportedPosition],
                                        into context: NSManagedObjectContext) -> Int {
        var added = 0
        for item in items {
            let request = CDFetchRequest(CDAlbumReadingPosition.self)
            request.predicate = NSPredicate(format: "albumID == %@", item.albumID)
            guard context.safeFetchFirst(request) == nil else { continue }
            let position = CDAlbumReadingPosition(context: context)
            position.albumID = item.albumID
            position.pageIndex = Int32(item.pageIndex)
            position.modifiedAt = item.updated ?? Date()
            added += 1
        }
        return added
    }

    private static func importHighlights(_ items: [ImportedHighlight],
                                         into context: NSManagedObjectContext) -> Int {
        var added = 0
        for item in items {
            let request = CDFetchRequest(CDAlbumHighlight.self)
            request.predicate = NSPredicate(
                format: "albumID == %@ AND pageIndex == %d AND text == %@",
                item.albumID, Int32(item.pageIndex), item.text
            )
            guard context.safeFetchFirst(request) == nil else { continue }
            let highlight = CDAlbumHighlight(context: context)
            highlight.albumID = item.albumID
            highlight.pageIndex = Int32(item.pageIndex)
            highlight.lessonTitle = item.lessonTitle
            highlight.text = item.text
            highlight.colorName = item.colorName ?? "yellow"
            highlight.setRectValues(item.rects ?? [])
            highlight.createdAt = item.created ?? Date()
            added += 1
        }
        return added
    }

    private static func importInk(_ items: [ImportedInk],
                                  into context: NSManagedObjectContext) -> Int {
        var added = 0
        for item in items where !item.drawingData.isEmpty {
            let request = CDFetchRequest(CDAlbumPageInk.self)
            request.predicate = NSPredicate(format: "albumID == %@ AND pageIndex == %d",
                                            item.albumID, Int32(item.pageIndex))
            guard context.safeFetchFirst(request) == nil else { continue }
            let ink = CDAlbumPageInk(context: context)
            ink.albumID = item.albumID
            ink.pageIndex = Int32(item.pageIndex)
            ink.drawingData = item.drawingData
            ink.modifiedAt = item.modified ?? Date()
            added += 1
        }
        return added
    }
}
