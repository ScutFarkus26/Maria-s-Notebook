// AlbumIdentityRepair.swift
// Albums are identified by their PDF's filename, which is what every
// annotation row, citation, scene-restoration value, and album window value
// carries. That keeps citations readable ("Biology Album.pdf, p. 42") but it
// means renaming or replacing a PDF used to orphan every bookmark, note,
// highlight, and Pencil drawing the guide had made in it — silently, with no
// error and no way back.
//
// Rather than change the key (which would churn citations, the MCP tools,
// scene storage, and the backup format), each album gets a cheap content
// fingerprint. The map of fingerprint → filename is recorded on every load;
// when an album turns up under a new name and the old name is gone from
// disk, the guide's work is carried across to the new one.

import CoreData
import CryptoKit
import Foundation
import OSLog
import PDFKit

enum AlbumIdentityRepair {

    /// Entities keyed by album filename. Every one of these has to move when
    /// an album is renamed, or the guide loses that part of their work.
    private static let albumScopedEntities = [
        "AlbumBookmark", "AlbumPageNote", "AlbumRecentVisit",
        "AlbumReadingPosition", "AlbumHighlight", "AlbumPageInk"
    ]

    // MARK: Fingerprinting

    /// A stable content fingerprint for one album.
    ///
    /// Built from the page count, the outline's lesson titles, and the text
    /// of the first page — all already parsed or cheap to read, and all
    /// independent of where the file lives or what it's called. Re-exporting
    /// an album with real content edits changes it, which is the correct
    /// outcome: that is a different album, not a renamed one.
    nonisolated static func fingerprint(pageCount: Int, lessonTitles: [String],
                                        firstPageText: String) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("pages:\(pageCount)\n".utf8))
        for title in lessonTitles {
            hasher.update(data: Data("\(title)\n".utf8))
        }
        let head = firstPageText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(600)
        hasher.update(data: Data(head.utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Repair

    /// Carries annotations across for any album that changed filename since
    /// the last load. Returns the renames it applied, oldID → newID.
    @discardableResult
    @MainActor
    static func repairRenamedAlbums(_ albums: [Album],
                                    in context: NSManagedObjectContext) -> [String: String] {
        var known = (UserDefaults.standard.dictionary(forKey: UserDefaultsKeys.albumsFingerprints)
                        as? [String: String]) ?? [:]
        let currentIDs = Set(albums.map(\.id))
        var applied: [String: String] = [:]

        for album in albums {
            let print = album.fingerprint
            guard let previousID = known[print] else {
                known[print] = album.id
                continue
            }
            guard previousID != album.id else { continue }
            // Only a rename if the old filename is genuinely gone. If both
            // are present the guide duplicated the PDF, and the copy has no
            // claim on the original's annotations.
            guard !currentIDs.contains(previousID) else { continue }

            remap(from: previousID, to: album.id, in: context)
            carryOverLastSeen(from: previousID, to: album.id)
            known[print] = album.id
            applied[previousID] = album.id
        }

        // Drop fingerprints whose album is no longer on the shelf at all, so
        // the map doesn't grow without bound across years of use.
        let live = Set(albums.map(\.fingerprint))
        known = known.filter { live.contains($0.key) }
        UserDefaults.standard.set(known, forKey: UserDefaultsKeys.albumsFingerprints)

        if !applied.isEmpty {
            Logger.albums.notice("Repaired \(applied.count, privacy: .public) renamed album(s)")
        }
        return applied
    }

    /// Rewrites every `albumID` foreign key from one filename to another.
    @MainActor
    static func remap(from oldID: String, to newID: String, in context: NSManagedObjectContext) {
        guard oldID != newID else { return }
        var moved = 0
        for entityName in albumScopedEntities {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "albumID == %@", oldID)
            for object in context.safeFetch(request) {
                object.setValue(newID, forKey: "albumID")
                object.setValue(Date(), forKey: "modifiedAt")
                moved += 1
            }
        }
        // Lessons linked to a page of this album travel with it.
        let lessons = CDFetchRequest(CDLesson.self)
        lessons.predicate = NSPredicate(format: "albumID == %@", oldID)
        for lesson in context.safeFetch(lessons) {
            lesson.albumID = newID
            moved += 1
        }
        if moved > 0 {
            context.safeSave()
            Logger.albums.notice(
                "Album renamed: moved \(moved, privacy: .public) row(s) to \(newID, privacy: .public)")
        }
    }

    /// The "Updated" badge baseline is keyed by filename too.
    private static func carryOverLastSeen(from oldID: String, to newID: String) {
        let key = UserDefaultsKeys.albumsLastSeenModDates
        guard var seen = UserDefaults.standard.dictionary(forKey: key) as? [String: Double],
              let value = seen.removeValue(forKey: oldID) else { return }
        seen[newID] = value
        UserDefaults.standard.set(seen, forKey: key)
    }
}
