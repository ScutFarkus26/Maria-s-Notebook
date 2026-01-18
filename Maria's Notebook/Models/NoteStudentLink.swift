// NoteStudentLink.swift
// Junction model for efficient multi-student note queries
//
// This model enables database-level filtering for notes with `.students([UUID])` scope.
// Instead of in-memory filtering of JSON-encoded scope data, we can now query
// NoteStudentLink records directly by studentID.

import Foundation
import SwiftData

/// A junction model linking Notes to Students for efficient querying.
/// Created automatically when a note's scope includes multiple students.
@Model
final class NoteStudentLink: Identifiable {
    // MARK: - Identity
    var id: UUID = UUID()

    /// The Note's ID as a string (for CloudKit compatibility)
    var noteID: String = ""

    /// The Student's ID as a string (for CloudKit compatibility)
    var studentID: String = ""

    /// Relationship to the Note - cascade delete when Note is deleted
    @Relationship var note: Note?

    // MARK: - Computed Properties

    var noteIDUUID: UUID? {
        get { UUID(uuidString: noteID) }
        set { noteID = newValue?.uuidString ?? "" }
    }

    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }

    // MARK: - Initializers

    init(id: UUID = UUID(), noteID: UUID, studentID: UUID, note: Note? = nil) {
        self.id = id
        self.noteID = noteID.uuidString
        self.studentID = studentID.uuidString
        self.note = note
    }

    init(id: UUID = UUID(), noteID: String, studentID: String, note: Note? = nil) {
        self.id = id
        self.noteID = noteID
        self.studentID = studentID
        self.note = note
    }
}
