//
//  StudentNotesTimelineView+BatchOperations.swift
//  Maria's Notebook
//
//  Extracted from StudentNotesTimelineView.swift
//

import SwiftUI
import CoreData

// MARK: - Batch Operations

extension StudentNotesTimelineList {

    func performBatchAction(_ action: (Set<UUID>) -> Void) {
        adaptiveWithAnimation {
            action(selectedNoteIDs)
            selectedNoteIDs.removeAll()
            isSelecting = false
        }
    }

    func batchDelete() {
        performBatchAction(viewModel.batchDelete(ids:))
    }

    func batchAddTag(_ tag: String) {
        performBatchAction { viewModel.batchAddTags([tag], for: $0) }
    }

    func batchRemoveTag(_ tag: String) {
        performBatchAction { viewModel.batchRemoveTags([tag], for: $0) }
    }

    func batchToggleFollowUp() {
        performBatchAction(viewModel.batchToggleFollowUp(for:))
    }

    func batchToggleReportFlag() {
        performBatchAction(viewModel.batchToggleReportFlag(for:))
    }

    func batchTogglePin() {
        performBatchAction(viewModel.batchTogglePin(for:))
    }
}
