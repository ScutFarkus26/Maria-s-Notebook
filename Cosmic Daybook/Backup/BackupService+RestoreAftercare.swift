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
    /// - A child with more than one link keeps one, the one `syncStudentLinks`
    ///   keeps (`CDNoteStudentLink.keeper`), so every device keeps the same.
    ///   A merge kept both the device's link and the backup's under another
    ///   id, so the note named the child twice (bug hunt 2026-10-29).
    /// - A child a multi-child scope names but no link covers gets one, with
    ///   the id every device gives it.
    func matchStudentLinksToScope() throws {
        for id in restoredNoteIDs {
            guard let note = try index.related(CDNote.self, id: id) else { continue }
            let (named, linkedByScope) = Self.studentsNamed(by: note.scope)
            var linksByStudent: [String: [CDNoteStudentLink]] = [:]
            for link in note.studentLinks?.allObjects as? [CDNoteStudentLink] ?? [] where !link.isDeleted {
                linksByStudent[link.studentID.uppercased(), default: []].append(link)
            }
            for (student, links) in linksByStudent {
                // A child the scope doesn't name stays only by a link the backup carries.
                let candidates = named.contains(student)
                    ? links : links.filter { $0.id.map(restoredLinkIDs.contains) == true }
                let keeper = CDNoteStudentLink.keeper(of: candidates, stableID: stableLinkID(note, student))
                for link in links where link !== keeper {
                    context.delete(link)
                }
            }
            for student in linkedByScope where linksByStudent[student.uuidString.uppercased()] == nil {
                let link = CDNoteStudentLink(context: context)
                if let noteID = note.id { link.id = CDNoteStudentLink.stableID(noteID: noteID, studentID: student) }
                link.noteID = note.id?.uuidString ?? ""
                link.studentID = student.uuidString
                link.note = note
            }
        }
    }

    /// The id every device gives `note`'s link to `student` (an uppercased
    /// id), when both ids are whole.
    private func stableLinkID(_ note: CDNote, _ student: String) -> UUID? {
        guard let noteID = note.id, let studentID = UUID(uuidString: student) else { return nil }
        return CDNoteStudentLink.stableID(noteID: noteID, studentID: studentID)
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
