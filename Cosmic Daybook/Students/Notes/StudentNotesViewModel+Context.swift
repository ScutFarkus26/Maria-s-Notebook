// StudentNotesViewModel+Context.swift
// How a note reads on a child's Notes tab (its date and what it's attached
// to), which notes Writing Help drafts from, and deleting photos.

import CoreData
import OSLog

extension StudentNotesViewModel {

    /// When a note was written. Its last edit moved it: pinning or flagging an
    /// old note dated it today, and a backdated Quick Note showed today.
    static func noteDate(_ note: CDNote) -> Date {
        note.createdAt ?? note.updatedAt ?? Date()
    }

    /// What a note on the tab's general list is attached to, in words. A
    /// check-in's note used to read "General Note".
    static func generalContext(for note: CDNote) -> String {
        if let lesson = note.lesson {
            let name = lesson.name.trimmed()
            return name.isEmpty ? "Lesson" : name
        }
        if let checkIn = note.workCheckIn {
            let title = (checkIn.work?.title ?? "").trimmed()
            return title.isEmpty ? "Check-In" : "Check-In: \(title)"
        }
        if note.workCompletionRecord != nil { return "Work Completed" }
        if let session = note.projectSession {
            let title = (session.project?.title ?? "").trimmed()
            return title.isEmpty ? "Project Session" : title
        }
        if note.practiceSession != nil { return "Practice" }
        return "General Note"
    }

    /// A project session's note made before 2026-10-10 is scoped to the whole
    /// class; it shows only to the project's members, not on every child's
    /// tab. Notes about named children, and notes not on a session, pass.
    func isOnProject(_ note: CDNote) -> Bool {
        guard note.scopeIsAll, let session = note.projectSession,
              let project = session.project, let studentID = student.id else { return true }
        let members = project.memberStudentUUIDs
        return members.isEmpty || members.contains(studentID)
    }

    // MARK: - Writing Help

    /// The notes Writing Help drafts from: the tab's own notes (so group
    /// notes are in, through their links) written within `range`. Meeting and
    /// attendance entries aren't notes and stay out. It used to read only
    /// this child's own and every year's whole-class notes.
    func writingHelpNotes(in range: DateRange?) -> [CDNote] {
        items
            .filter { $0.isNote && (range?.contains($0.date) ?? true) }
            .compactMap { fetchNote(id: $0.id) }
    }

    // MARK: - Photos

    /// Deletes note photos whose notes are gone. Called only after the delete
    /// has saved.
    static func deletePhotos(_ paths: [String?]) {
        for path in paths {
            guard let path, !path.isEmpty else { continue }
            do {
                try PhotoStorageService.deleteImage(filename: path)
            } catch {
                Logger.notes.warning("Failed to delete a deleted note's photo: \(error.localizedDescription)")
            }
        }
    }
}

extension UnifiedNoteItem {
    /// Whether the row is one of the guide's notes (a `CDNote`) — not a
    /// meeting's fields or an attendance record's note, which only show here.
    var isNote: Bool {
        switch source {
        case .general, .lesson, .work, .presentation: return true
        case .meeting, .attendance: return false
        }
    }
}
