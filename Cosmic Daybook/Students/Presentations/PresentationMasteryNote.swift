//
//  PresentationMasteryNote.swift
//  Cosmic Daybook
//
//  The quiet note on a "Who was there?" tile when the child already has a
//  mastery mark for the lesson ("mastered Sep 12"). Presenting again keeps the
//  mark; the note only says she has it.
//

import Foundation

enum PresentationMasteryNote {

    /// "mastered Sep 12", "mastered Sep 12, 2025" outside `now`'s year, or "mastered"
    /// when the mark has no date.
    static func text(masteredOn date: Date?, now: Date = Date(), calendar: Calendar = AppCalendar.shared) -> String {
        guard let date else { return "mastered" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if !sameYear { style = style.year() }
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return "mastered \(date.formatted(style))"
    }
}
