//
//  StudentRecordCaption.swift
//  Maria's Notebook
//
//  "Given Mar 11, 2026" — the one line a picker owes the guide before she
//  plans a lesson somebody has already had.
//
//  Every picker that can form a group for a lesson shows it the same way, so
//  a repeat is visible where the choice is made rather than only in the
//  refusal afterwards. The record it reads is `PresentationRecordIndex`, the
//  same definition of "already has it" the regive guard uses.
//

import SwiftUI

struct StudentRecordCaption: View {
    let given: PresentationRecordIndex.Given

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle")
            Text(Self.text(for: given))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    /// `"Given Mar 11, 2026"`, or `"Given previously"` when the only record is
    /// an undated mark.
    static func text(for given: PresentationRecordIndex.Given) -> String {
        guard let day = given.days.last else { return "Given previously" }
        return "Given \(DateFormatters.mediumDate.string(from: day))"
    }
}
