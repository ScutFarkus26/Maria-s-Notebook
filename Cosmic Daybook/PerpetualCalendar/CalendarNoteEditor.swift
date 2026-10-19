// CalendarNoteEditor.swift
// Inline day-note editing for the planning calendar: the day's pad.

import CoreData
import Foundation
import SwiftUI

/// Holds the day cell whose text field is open and the text being typed into
/// it, and writes the draft back to that day's pad (`CDDayPad`) on commit.
///
/// A day has one note, its pad: the Calendar, Today's Pad and the Claude tools
/// read and write the same text (Simplify the app, Phase 7). The Calendar's
/// own notes (`CDCalendarNote`) were copied into the pads at launch
/// (`CalendarNotePadCopy`) and are no longer written.
///
/// Tap a day, type, hit return (or click away), and opening a second day
/// commits the first, so the rules for what a commit writes live here.
@Observable
final class CalendarNoteEditor {

    /// The cell whose text field is open, if any.
    var editingCell: CellID?

    /// The text bound to the open text field.
    var draft: String = ""

    /// What the open field started with: a commit that leaves it as it was
    /// writes nothing.
    private var openingText = ""

    /// The day's pad text when the field opened: what a save is measured
    /// against, so a change made meanwhile on another device or on Today is
    /// kept rather than written over (`TodayDataFetcher.savePadText`).
    private var openingPadText = ""

    /// Whether the open field holds more than one line: the pad written on
    /// Today can, and its field then wraps rather than flattening the lines.
    var editsMultipleLines: Bool { openingText.contains(where: \.isNewline) }

    /// Open `cellID` for editing, committing whichever cell was open before.
    /// `padTexts` is each day's pad text, as the grid shows it.
    func beginEditing(
        _ cellID: CellID,
        padTexts: [CellID: String],
        in context: NSManagedObjectContext
    ) {
        if let previous = editingCell, previous != cellID {
            commit(previous, in: context)
        }
        let padText = padTexts[cellID] ?? ""
        let opening = Self.openingText(for: cellID, padText: padText)
        draft = opening
        openingText = opening
        openingPadText = padText
        editingCell = cellID
    }

    /// What a day's field opens with: its pad's text, whatever the grid's
    /// layers show, else the holiday it falls on, else nothing. The grid used
    /// to pass what it showed, so with the Notes layer hidden the field opened
    /// empty (or with the holiday) and the commit that followed deleted or
    /// overwrote the hidden note (2026-10-17 hunt, #8).
    static func openingText(for cellID: CellID, padText: String) -> String {
        if !padText.trimmed().isEmpty {
            return padText
        }
        return PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year) ?? ""
    }

    /// Write the draft to `cellID`'s pad and close the text field.
    ///
    /// A draft left as the field opened writes nothing. A note that is
    /// emptied, or typed back to the holiday name it was standing in for,
    /// empties the pad, and the holiday shows again. The pad is looked up
    /// again first, and a change made to it since the field opened is kept,
    /// with what she typed added after it. Her text is saved trimmed, so the
    /// merge compares the three texts trimmed too (`TodayDataFetcher.mergedPadText`):
    /// a pad that opened ending in a line break used to go in again whole.
    func commit(_ cellID: CellID, in context: NSManagedObjectContext) {
        let trimmed = draft.trimmed()
        let unchanged = trimmed == openingText.trimmed()
        let base = openingPadText
        editingCell = nil
        draft = ""
        openingText = ""
        openingPadText = ""
        guard !unchanged, let day = cellID.startOfDay() else { return }

        let holiday = PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year)
        let text = trimmed == holiday ? "" : trimmed
        _ = TodayDataFetcher.savePadText(text, base: base, day: day, context: context)
        if context.hasChanges {
            context.safeSave()
        }
    }

    /// Commits `cellID` only while it is still the open cell. Leaving a day's
    /// field (focus moving away, the calendar going off screen) commits the
    /// note, which used to be kept only on Return or when another day opened
    /// (2026-10-11 hunt, #41). The check matters because opening a second day
    /// commits the first and moves the draft to the second, and the first
    /// field's focus loss can arrive after that: it must not write the second
    /// day's text into the first.
    func commitIfOpen(_ cellID: CellID, in context: NSManagedObjectContext) {
        guard editingCell == cellID else { return }
        commit(cellID, in: context)
    }

    /// Commits whichever day is open, if any (the calendar going away).
    func commitOpenCell(in context: NSManagedObjectContext) {
        guard let open = editingCell else { return }
        commit(open, in: context)
    }
}

// MARK: - Pad lookup

extension CalendarNoteEditor {

    /// Each day's pad text keyed by its cell, as a join of the day's copies
    /// would leave it (`TodayDataFetcher.joinedText`), without joining them;
    /// days whose pads hold nothing but spaces are left out.
    static func padTexts(of pads: some Sequence<CDDayPad>) -> [CellID: String] {
        var padsByCell: [CellID: [CDDayPad]] = [:]
        for pad in pads where !pad.isDeleted {
            guard let day = pad.day else { continue }
            padsByCell[CellID(date: day), default: []].append(pad)
        }
        var lookup: [CellID: String] = [:]
        for (cell, dayPads) in padsByCell {
            let text = TodayDataFetcher.joinedText(of: TodayDataFetcher.joinOrder(dayPads))
            if !text.trimmed().isEmpty { lookup[cell] = text }
        }
        return lookup
    }
}

// MARK: - Shown in a cell

extension CalendarDayText {

    /// A pad's text on one line of a day cell: each line that has writing on
    /// it, trimmed, joined with a middle dot.
    static func padSummary(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
    }
}
