// BackupService+RestoreAftercare.swift
// What a restore does around its records: the student links its notes need,
// the denormalized day it repairs after saving, the album warning it gives,
// and how it says it failed after its save.

import CoreData
import Foundation

/// A restore that failed after its records were saved: the store holds the
/// restore, so a replace restore goes back to its checkpoint
/// (`BackupTransactionManager.executeWithRollback`). A failure before the
/// save leaves the notebook as it was, and nothing is rolled back.
nonisolated struct BackupRestoreSavedError: LocalizedError {
    let underlying: any Error

    var errorDescription: String? { (underlying as? any LocalizedError)?.errorDescription }
}

extension BackupService {

    // MARK: - Album Reattachment

    /// Album bookmarks, notes, highlights, and ink key on the album PDF's
    /// filename. They restore intact, but on a device with no album folder
    /// registered they have nothing to attach to until the guide adds one —
    /// say so, rather than letting them look lost. `albumIDs` holds every
    /// album the restored bookmarks, page notes, highlights, ink and reading
    /// positions name (`BackupRestoreRun.albumIDs`).
    func albumReattachWarning(for albumIDs: Set<String>) -> String? {
        guard !albumIDs.isEmpty, !AlbumLibrary.hasResolvableFolderBookmark() else { return nil }
        let noun = albumIDs.count == 1 ? "album" : "albums"
        return "This backup includes bookmarks, notes, highlights, or drawings for "
            + "\(albumIDs.count) \(noun). Open Albums and add your album folder to reattach them."
    }

    // MARK: - Denormalized Fields

    func repairDenormalizedFields(viewContext: NSManagedObjectContext) throws {
        let assignmentsForRepair = try viewContext.fetch(
            CDFetchRequest(CDLessonAssignment.self)
        )
        var repairedCount = 0
        for la in assignmentsForRepair {
            let correct = la.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
            if la.scheduledForDay != correct {
                la.scheduledForDay = correct
                repairedCount += 1
            }
        }
        if repairedCount > 0 {
            try viewContext.save()
        }
    }
}

extension BackupRestoreRun {

    /// Gives each restored note the student links its scope calls for, as
    /// every note writer does (`CDNote.syncStudentLinks`), without dropping
    /// any link the backup carries. A merge restore that changed a note's
    /// scope left the links of its old scope beside the backup's (so the note
    /// still showed under a child it no longer names), and a backup without a
    /// note's links left it with none (so it showed under no one).
    ///
    /// - A link this device had that the restored scope doesn't name is
    ///   removed; one the backup carries stays, as every backed-up row does.
    /// - A child a multi-child scope names but no link covers gets one.
    func matchStudentLinksToScope() throws {
        for id in restoredNoteIDs {
            guard let note = try index.related(CDNote.self, id: id) else { continue }
            let (named, linkedByScope) = Self.studentsNamed(by: note.scope)
            var covered = Set<String>()
            for link in note.studentLinks?.allObjects as? [CDNoteStudentLink] ?? [] where !link.isDeleted {
                let student = link.studentID.uppercased()
                if named.contains(student) || link.id.map(restoredLinkIDs.contains) == true {
                    covered.insert(student)
                } else {
                    context.delete(link)
                }
            }
            for student in linkedByScope where covered.insert(student.uuidString.uppercased()).inserted {
                let link = CDNoteStudentLink(context: context)
                link.noteID = note.id?.uuidString ?? ""
                link.studentID = student.uuidString
                link.note = note
            }
        }
    }

    /// The children a scope names (uppercased ids), and those it gives a
    /// link each: only a multi-child scope does (`syncStudentLinks`), but a
    /// one-child note's link to its child is no stray.
    private static func studentsNamed(by scope: NoteScope) -> (named: Set<String>, linked: [UUID]) {
        switch scope {
        case .all: ([], [])
        case .student(let student): ([student.uuidString.uppercased()], [])
        case .students(let students): (Set(students.map { $0.uuidString.uppercased() }), students)
        }
    }
}
