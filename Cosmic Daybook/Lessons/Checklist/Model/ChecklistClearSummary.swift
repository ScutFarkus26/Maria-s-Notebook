//
//  ChecklistClearSummary.swift
//  Cosmic Daybook
//
//  Clear takes a child off a cell for good, history included, and one Delete
//  key or the selection bar's Clear does it with no undo. So when the cells
//  hold something that happened (a given presentation, a mastery mark,
//  finished work) the checklist asks first, naming how much, as a lesson
//  delete does. A cell holding only plans and open work clears straight away.
//

import Foundation

/// What clearing some cells would take out of the children's history.
struct ChecklistClearSummary: Equatable {
    var cells = 0
    var givenPresentations = 0
    var masteryMarks = 0
    var finishedWork = 0

    /// Whether the guide is asked first.
    var needsConfirmation: Bool { givenPresentations + masteryMarks + finishedWork > 0 }

    var title: String {
        cells == 1 ? "Clear This Cell?" : "Clear \(cells) Cells?"
    }

    /// "Clearing takes 1 given presentation and 1 mastery mark out of Maya S's
    /// history. Notes stay in Maya S's notes. This can't be undone."
    func message(childName: String?) -> String {
        var going: [String] = []
        if givenPresentations > 0 {
            going.append(Self.count(givenPresentations, "given presentation", "given presentations"))
        }
        if masteryMarks > 0 { going.append(Self.count(masteryMarks, "mastery mark", "mastery marks")) }
        if finishedWork > 0 {
            going.append(Self.count(finishedWork, "finished work item", "finished work items"))
        }
        let list = ListFormatter.localizedString(byJoining: going)
        let name = childName?.trimmingCharacters(in: .whitespaces) ?? ""
        if cells == 1 {
            let whose = name.isEmpty ? "this child's" : "\(name)'s"
            return "Clearing takes \(list) out of \(whose) history. Notes stay in \(whose) notes. "
                + "This can't be undone."
        }
        return "Clearing these \(cells) cells takes \(list) out of the children's history. "
            + "Notes stay in each child's notes. This can't be undone."
    }

    private static func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value) \(value == 1 ? one : many)"
    }
}

/// A Clear waiting for the guide's yes.
struct ChecklistClearRequest: Equatable {
    let cells: Set<CellIdentifier>
    let summary: ChecklistClearSummary
    /// From the selection bar (the selection ends when it runs) or one cell.
    let fromSelection: Bool
    /// The child's name, for one cell.
    let childName: String?

    var title: String { summary.title }
    var message: String { summary.message(childName: childName) }
}
