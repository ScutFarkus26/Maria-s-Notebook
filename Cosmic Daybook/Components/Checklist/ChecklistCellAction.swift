//
//  ChecklistCellAction.swift
//  Cosmic Daybook
//
//  What a checklist cell can ask for, and the one entry point every cell sends it
//  through. A cell used to carry six closures, which made every cell differ from
//  its last render on every grid update; now its inputs are plain values and the
//  grid owns the single handler.
//

import CoreGraphics
import Foundation

enum ChecklistCellAction: String {
    /// A click: opens the cell's card, or with ⌘ / Shift held (or in the iPhone's
    /// Select mode) changes the selection. The grid reads the modifier keys.
    case click
    /// Closes the cell's card.
    case closeCard
    /// Add to the Inbox, or take the plan off again.
    case toggleScheduled
    /// Add to, or take out of, the multi-selection.
    case toggleSelection
    case togglePresented
    case togglePreviouslyPresented
    /// The card's ladder steps and the keys: move the child up to the rung, never down.
    case markPresented
    case markPracticing
    case markReviewing
    case markComplete
    case clearStatus
    /// Card buttons that open something: the present-a-lesson sheet, the new-work sheet,
    /// the lesson, the student. The grid handles these; the view model never sees them.
    case present
    case assignWork
    case openLesson
    case openStudent
}

/// The grid's one handler for every cell. Compares equal to any other handler: it
/// routes by the cell's IDs to the same view model, so a new closure on each grid
/// render is not a change the cell needs to redraw for.
struct ChecklistCellActionHandler: Equatable {
    let perform: (ChecklistCellAction, CellIdentifier) -> Void

    func callAsFunction(_ action: ChecklistCellAction, _ cell: CellIdentifier) {
        perform(action, cell)
    }

    static func == (lhs: ChecklistCellActionHandler, rhs: ChecklistCellActionHandler) -> Bool { true }
}

/// The grid's handler for a drag that starts on a cell (Mac): where in the cell it began
/// and how far it has gone, so the grid can find the row or column it has reached.
/// Compares equal to any other, like the action handler.
struct ChecklistCellDragHandler: Equatable {
    let changed: (CellIdentifier, CGPoint, CGSize) -> Void
    let ended: (CellIdentifier) -> Void

    static func == (lhs: ChecklistCellDragHandler, rhs: ChecklistCellDragHandler) -> Bool { true }
}
