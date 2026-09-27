// BackupNoteLinks.swift
// What the end-of-restore note relink needs from a restored note.

import Foundation

/// A restored note's id and the ids of the records it points at. Notes import
/// early and most of their targets later, so the restore keeps these — not the
/// notes' rows — until every target type is in, then relinks
/// (`BackupEntityImporter.relinkNoteRelationships`).
nonisolated struct BackupNoteLinks: Sendable {
    let noteID: UUID
    let workID: UUID?
    let lessonAssignmentID: UUID?
    let attendanceRecordID: UUID?
    let workCheckInID: UUID?
    let workCompletionRecordID: UUID?
    let studentMeetingID: UUID?
    let projectSessionID: UUID?
    let reminderID: UUID?
    let practiceSessionID: UUID?
    let issueID: UUID?

    /// Nil for a note that points at nothing the relink sets; relinking it
    /// would only look the note up.
    init?(_ note: NoteDTO) {
        let targets: [UUID?] = [
            note.workID, note.lessonAssignmentID, note.attendanceRecordID, note.workCheckInID,
            note.workCompletionRecordID, note.studentMeetingID, note.projectSessionID,
            note.reminderID, note.practiceSessionID, note.issueID
        ]
        guard targets.contains(where: { $0 != nil }) else { return nil }
        noteID = note.id
        workID = note.workID
        lessonAssignmentID = note.lessonAssignmentID
        attendanceRecordID = note.attendanceRecordID
        workCheckInID = note.workCheckInID
        workCompletionRecordID = note.workCompletionRecordID
        studentMeetingID = note.studentMeetingID
        projectSessionID = note.projectSessionID
        reminderID = note.reminderID
        practiceSessionID = note.practiceSessionID
        issueID = note.issueID
    }
}
