//
//  ChecklistSelection.swift
//  Cosmic Daybook
//
//  The checklist's selection rules without a Select mode: Shift-click and a drag
//  reach along one row or down one column, the keyboard cursor steps through the
//  cells on screen, and "ready" picks the children a lesson can be given to now.
//  Pure functions over IDs, so the rules are tested without a grid.
//

import Foundation

enum ChecklistSelection {

    /// The cells from `anchor` to `target`, both included: along the row when they share
    /// a lesson, down the column when they share a child, in the order the grid draws
    /// them. Any other pair, or a cell not on screen, is just the target.
    static func range(
        from anchor: CellIdentifier,
        to target: CellIdentifier,
        lessonOrder: [UUID],
        studentOrder: [UUID]
    ) -> [CellIdentifier] {
        if anchor.lessonID == target.lessonID,
           let from = studentOrder.firstIndex(of: anchor.studentID),
           let to = studentOrder.firstIndex(of: target.studentID) {
            return studentOrder[min(from, to)...max(from, to)].map {
                CellIdentifier(studentID: $0, lessonID: target.lessonID)
            }
        }
        if anchor.studentID == target.studentID,
           let from = lessonOrder.firstIndex(of: anchor.lessonID),
           let to = lessonOrder.firstIndex(of: target.lessonID) {
            return lessonOrder[min(from, to)...max(from, to)].map {
                CellIdentifier(studentID: target.studentID, lessonID: $0)
            }
        }
        return [target]
    }

    /// `selection` with `cell` added, or taken out when it was already in.
    static func toggling(_ cell: CellIdentifier, in selection: Set<CellIdentifier>) -> Set<CellIdentifier> {
        var result = selection
        if result.remove(cell) == nil { result.insert(cell) }
        return result
    }

    /// The keyboard cursor moved `dx` columns and `dy` rows, stopping at the edges. With
    /// no cursor yet, or one whose row or column is gone, it lands on the first cell.
    static func moving(
        _ cursor: CellIdentifier?,
        dx: Int,
        dy: Int,
        lessonOrder: [UUID],
        studentOrder: [UUID]
    ) -> CellIdentifier? {
        guard let firstLesson = lessonOrder.first, let firstStudent = studentOrder.first else { return nil }
        guard let cursor,
              let row = lessonOrder.firstIndex(of: cursor.lessonID),
              let column = studentOrder.firstIndex(of: cursor.studentID)
        else {
            return CellIdentifier(studentID: firstStudent, lessonID: firstLesson)
        }
        let newRow = min(max(row + dy, 0), lessonOrder.count - 1)
        let newColumn = min(max(column + dx, 0), studentOrder.count - 1)
        return CellIdentifier(studentID: studentOrder[newColumn], lessonID: lessonOrder[newRow])
    }

    /// The children, in column order, who are Ready for `lessonID`: not presented, not
    /// planned, nothing holding them back (the cell's Ready mark). `excluding` leaves out
    /// the child a card is open for, so "Present with 4 others ready" counts the others.
    static func readyStudents(
        for lessonID: UUID,
        studentOrder: [UUID],
        matrix: [UUID: [UUID: StudentChecklistRowState]],
        excluding excluded: UUID? = nil
    ) -> [UUID] {
        studentOrder.filter { studentID in
            studentID != excluded && matrix[studentID]?[lessonID]?.displayStatus == .ready
        }
    }
}
