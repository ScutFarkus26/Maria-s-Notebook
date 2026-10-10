// ClassAreaChecklistViewModel+Clearing.swift
// Clear from a cell (menu, card, Delete key) or the selection bar: straight away when the
// cells hold only plans and open work, otherwise held in `pendingClear` until the guide
// says yes (`ChecklistClearSummary`).

import CoreData
import Foundation

extension ClassAreaChecklistViewModel {

    /// One cell's Clear. Returns true when it ran; false when it waits in `pendingClear`.
    @discardableResult
    func requestClear(_ cell: CellIdentifier, context: NSManagedObjectContext) -> Bool {
        let summary = ChecklistCellRecords.clearSummary(for: [cell], in: context)
        guard summary.needsConfirmation else {
            clear(cell, context: context)
            return true
        }
        let name = rosterStudents.first { $0.id == cell.studentID }?.shortName
        pendingClear = ChecklistClearRequest(cells: [cell], summary: summary, fromSelection: false, childName: name)
        return false
    }

    /// The selection bar's Clear. Returns true when it ran; false when it waits in `pendingClear`.
    @discardableResult
    func requestBatchClear(context: NSManagedObjectContext) -> Bool {
        let cells = selectedCells
        guard !cells.isEmpty else { return true }
        let summary = ChecklistCellRecords.clearSummary(for: cells, in: context)
        guard summary.needsConfirmation else {
            batchClearStatus(context: context)
            return true
        }
        pendingClear = ChecklistClearRequest(cells: cells, summary: summary, fromSelection: true, childName: nil)
        return false
    }

    /// The guide said yes: clears exactly the cells she was asked about.
    func confirmClear(_ request: ChecklistClearRequest, context: NSManagedObjectContext) {
        pendingClear = nil
        if request.fromSelection {
            ChecklistBatchActionExecutor.batchClearStatus(
                selectedCells: request.cells, students: students, lessons: lessons, context: context
            )
            recomputeMatrix(context: context)
            clearSelection()
        } else if let cell = request.cells.first {
            clear(cell, context: context)
        }
    }

    func cancelClear() {
        pendingClear = nil
    }

    private func clear(_ cell: CellIdentifier, context: NSManagedObjectContext) {
        guard let student = rosterStudents.first(where: { $0.id == cell.studentID }),
              let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { return }
        clearStatus(student: student, lesson: lesson, context: context)
    }
}
