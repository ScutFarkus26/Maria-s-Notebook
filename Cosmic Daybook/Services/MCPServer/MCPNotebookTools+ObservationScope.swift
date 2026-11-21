//
//  MCPNotebookTools+ObservationScope.swift
//  Cosmic Daybook
//
//  The scope update_observation's `student_names` gives a note, read as the
//  note editor reads its picker (`NoteScope.forSelection`).
//

import CoreData
import Foundation

extension MCPNotebookTools {

    static let wholeClassDescription = "now a whole-class note"

    /// The scope `studentIDs` gives `note`, and the receipt lines. No
    /// children on a presentation's note means the children who had it, as
    /// the note editor reads an empty pick, not the whole class (domain logic
    /// review A20). Nil `studentIDs` leaves the scope alone.
    static func resolvedNoteScope(
        studentIDs: [UUID]?, descriptions: [String], for note: CDNote
    ) -> (NoteScope?, [String]) {
        guard let ids = studentIDs else { return (nil, descriptions) }
        let roster = note.lessonAssignment?.resolvedStudentIDs ?? []
        let scope = NoteScope.forSelection(Set(ids), fallback: roster)
        var lines = descriptions
        if ids.isEmpty, scope != .all, let index = lines.firstIndex(of: wholeClassDescription) {
            lines[index] = "now about the children who had its presentation"
        }
        return (scope, lines)
    }
}
