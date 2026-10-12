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

    /// Commits `cellID` only while it is still the open cell. Leaving a day's
    /// field (focus moving away, the calendar going off screen) commits the
    /// note, which used to be kept only on Return or when another day opened
    /// (2026-10-11 hunt, #41). The check matters because opening a second day
    /// commits the first and moves the draft to the second, and the first
    /// field's focus loss can arrive after that: it must not write the second
    /// day's text into the first.
    func commitIfOpen(
        _ cellID: CellID,
        notes: [CellID: CDCalendarNote],
        in context: NSManagedObjectContext
    ) {
        guard editingCell == cellID else { return }
        commit(cellID, notes: notes, in: context)
    }

    /// Commits whichever day is open, if any (the calendar going away).
    func commitOpenCell(notes: [CellID: CDCalendarNote], in context: NSManagedObjectContext) {
        guard let open = editingCell else { return }
        commit(open, notes: notes, in: context)
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
