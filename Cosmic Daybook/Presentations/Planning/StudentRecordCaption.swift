//
//  StudentRecordCaption.swift
//  Cosmic Daybook
//
//  "had this Mar 11 ×2" — the one line a picker owes the guide before she
//  plans a lesson somebody has already had.
//
//  Every picker that can form a group for a lesson shows it the same way, so
//  a repeat is visible where the choice is made rather than only in the
//  refusal afterwards. The record it reads is `PresentationRecordIndex`, the
//  same definition of "already has it" the regive guard uses.
//
//  The wording is deliberately short: the year is dropped for a lesson given
//  this year, and a lesson given more than once says how many times rather
//  than listing days, because the list is what `student_presentation_history`
//  is for.
//

import SwiftUI

struct StudentRecordCaption: View {
    let given: PresentationRecordIndex.Given
    /// Inside a selected-chip capsule there is no room for the glyph, and the
    /// tick on the chip already says she is in the group.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if !compact {
                Image(systemName: "checkmark.circle")
            }
            Text(Self.text(for: given))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityText(for: given))
    }

    /// `"had this Mar 11"` this year, `"had this Mar 11, 2025"` in an earlier
    /// year, `"had this Mar 11 ×2"` when the record holds more than one day,
    /// and `"had this before"` when the only record is an undated mark.
    static func text(for given: PresentationRecordIndex.Given, now: Date = Date()) -> String {
        guard let day = given.days.last else { return "had this before" }
        let times = given.days.count > 1 ? " ×\(given.days.count)" : ""
        return "had this \(dayText(day, now: now))\(times)"
    }

    /// The same sentence with "×2" spelled out, so a screen reader says
    /// "2 times" rather than a multiplication sign.
    static func accessibilityText(
        for given: PresentationRecordIndex.Given, now: Date = Date()
    ) -> String {
        guard let day = given.days.last else { return "had this before" }
        let times = given.days.count > 1 ? ", \(given.days.count) times" : ""
        return "had this \(dayText(day, now: now))\(times)"
    }

    /// The year is noise for a lesson given this school year and the whole
    /// point for one given before it.
    private static func dayText(_ day: Date, now: Date) -> String {
        let calendar = AppCalendar.shared
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        let formatter = sameYear ? DateFormatters.shortMonthDay : DateFormatters.mediumDate
        return formatter.string(from: day)
    }
}
