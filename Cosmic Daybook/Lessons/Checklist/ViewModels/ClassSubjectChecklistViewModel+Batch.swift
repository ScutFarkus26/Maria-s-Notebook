// ClassAreaChecklistViewModel+Batch.swift
// The selection bar's marks (`ChecklistBatchActionExecutor`), each saved once for the
// whole selection and taken back if the save fails (+Saving).

import CoreData
import Foundation

extension ClassAreaChecklistViewModel {

    func batchAddToInbox(context: NSManagedObjectContext) {
        saveChange("Checklist: add the selection to the Inbox", context: context) {
            ChecklistBatchActionExecutor.batchAddToInbox(
                selectedCells: selectedCells,
                students: students,
                lessons: lessons,
                matrixStates: matrixStates,
                context: context
            )
        }
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchMarkPresented(context: NSManagedObjectContext) {
        saveChange("Checklist: mark the selection presented", context: context) {
            ChecklistBatchActionExecutor.batchMarkPresented(
                selectedCells: selectedCells,
                students: students,
                lessons: lessons,
                matrixStates: matrixStates,
                context: context
            )
        }
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchMarkPreviouslyPresented(context: NSManagedObjectContext) {
        saveChange("Checklist: mark the selection previously presented", context: context) {
            ChecklistBatchActionExecutor.batchMarkPreviouslyPresented(
                selectedCells: selectedCells,
                students: students,
                lessons: lessons,
                matrixStates: matrixStates,
                context: context
            )
        }
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchMarkProficient(context: NSManagedObjectContext) {
        saveChange("Checklist: mark the selection mastered", context: context) {
            ChecklistBatchActionExecutor.batchMarkProficient(
                selectedCells: selectedCells,
                students: students,
                lessons: lessons,
                matrixStates: matrixStates,
                context: context
            )
        }
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchClearStatus(context: NSManagedObjectContext) {
        clearCells(selectedCells, context: context)
        clearSelection()
    }

    /// The selection's Clear, by the cell's own rule (`ChecklistCellRecords.clear`).
    func clearCells(_ cells: Set<CellIdentifier>, context: NSManagedObjectContext) {
        saveChange("Checklist: clear the selection", context: context) {
            ChecklistBatchActionExecutor.batchClearStatus(
                selectedCells: cells,
                students: students,
                lessons: lessons,
                context: context
            )
        }
        recomputeMatrix(context: context)
    }
}
