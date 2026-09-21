// CalendarNoteEditor.swift
// Inline day-note editing shared by the calendar grids.

import CoreData
import Foundation
import SwiftUI

/// Holds the day cell whose text field is open and the text being typed into
/// it, and writes the draft back to its `CDCalendarNote` on commit.
///
/// Both calendar grids edit notes the same way — tap a day, type, hit return,
/// and opening a second day commits the first — so the rules for when a note
/// is created, updated or deleted live here instead of in each view.
@Observable
final class CalendarNoteEditor {

    /// The cell whose text field is open, if any.
    var editingCell: CellID?

    /// The text bound to the open text field.
    var draft: String = ""

    /// Open `cellID` for editing, committing whichever cell was open before.
    func beginEditing(
        _ cellID: CellID,
        currentText: String,
        notes: [CellID: CDCalendarNote],
        in context: NSManagedObjectContext
    ) {
        if let previous = editingCell, previous != cellID {
            commit(previous, notes: notes, in: context)
        }
        draft = currentText
        editingCell = cellID
    }

    /// Write the draft back to `cellID` and close the text field.
    ///
    /// A note that is emptied, or typed back to the holiday name it was
    /// standing in for, is deleted rather than stored.
    func commit(
        _ cellID: CellID,
        notes: [CellID: CDCalendarNote],
        in context: NSManagedObjectContext
    ) {
        let trimmed = draft.trimmed()
        let holiday = PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year)

        if let existing = notes[cellID] {
            if trimmed.isEmpty || trimmed == holiday {
                context.delete(existing)
            } else {
                existing.text = trimmed
                existing.modifiedAt = Date()
            }
        } else if !trimmed.isEmpty && trimmed != holiday {
            let newNote = CDCalendarNote(context: context)
            newNote.year = Int64(cellID.year)
            newNote.month = Int64(cellID.month)
            newNote.day = Int64(cellID.day)
            newNote.text = trimmed
        }

        context.safeSave()
        editingCell = nil
        draft = ""
    }
}

// MARK: - Note lookup

extension FetchedResults where Result == CDCalendarNote {

    /// The fetched notes keyed by the day cell they belong to.
    var byCell: [CellID: CDCalendarNote] {
        var lookup: [CellID: CDCalendarNote] = [:]
        for note in self {
            lookup[CellID(year: Int(note.year), month: Int(note.month), day: Int(note.day))] = note
        }
        return lookup
    }
}
