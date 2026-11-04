//
//  ChecklistRemovalRequest.swift
//  Cosmic Daybook
//
//  Unmark Presented and Remove Plan take one child off a presentation or a
//  plan. When she was the only child on it, the record itself goes, and one
//  click used to delete a given presentation, or a plan with notes on it,
//  without a word (bug hunt 2026-11-03 #2). Its notes stay hers either way
//  (`ChecklistRosterRemoval.remove`); this is the question the Checklist asks
//  first, naming what goes, as a cell's Clear asks (`ChecklistClearSummary`).
//  Taking her off a group, or deleting a plain plan with nothing on it, asks
//  nothing.
//

import Foundation

/// What taking a child off a record would delete, when that is worth asking about.
struct ChecklistRemovalSummary: Equatable {
    /// The record goes is a given presentation (Unmark Presented), not a plan (Remove Plan).
    let wasGiven: Bool
    /// The day it was given; nil for a plan or an undated "previously presented" mark.
    let givenOn: Date?
    /// Notes on the record, and history rows with text, that become notes on her.
    let noteCount: Int

    /// Asked about only when the record goes and it was given or carries notes.
    var needsConfirmation: Bool { wasGiven || noteCount > 0 }

    var title: String { wasGiven ? "Unmark Presented?" : "Remove This Plan?" }

    var confirmLabel: String { wasGiven ? "Unmark" : "Remove Plan" }

    /// "This deletes Maya S's presentation of Decimal 0 from Oct 20. Its 2 notes stay in
    /// Maya S's notes, and mastery marks stay."
    func message(childName: String?, lessonName: String?) -> String {
        let name = childName?.trimmingCharacters(in: .whitespaces) ?? ""
        let whose = name.isEmpty ? "this child's" : "\(name)'s"
        let lesson = lessonName?.trimmingCharacters(in: .whitespaces) ?? ""
        let what: String
        if wasGiven {
            var record = lesson.isEmpty ? "presentation" : "presentation of \(lesson)"
            if let givenOn {
                record += " from \(givenOn.formatted(.dateTime.month(.abbreviated).day()))"
            }
            what = "This deletes \(whose) \(record), since no other child was on it."
        } else {
            let record = lesson.isEmpty ? "plan" : "plan for \(lesson)"
            what = "This deletes \(whose) \(record), since no other child was on it."
        }
        var kept: [String] = []
        if noteCount > 0 {
            let notes = noteCount == 1 ? "Its note stays" : "Its \(noteCount) notes stay"
            kept.append("\(notes) in \(whose) notes")
        }
        if wasGiven { kept.append("mastery marks stay") }
        guard !kept.isEmpty else { return what }
        let rest = ListFormatter.localizedString(byJoining: kept)
        return "\(what) \(rest.prefix(1).uppercased())\(rest.dropFirst())."
    }
}

/// An Unmark Presented or Remove Plan waiting for the guide's yes.
struct ChecklistRemovalRequest: Equatable {
    let cell: CellIdentifier
    /// `.togglePresented`, `.togglePreviouslyPresented` or `.toggleScheduled`.
    let action: ChecklistCellAction
    let summary: ChecklistRemovalSummary
    let childName: String?
    let lessonName: String?

    var title: String { summary.title }
    var message: String { summary.message(childName: childName, lessonName: lessonName) }
}
