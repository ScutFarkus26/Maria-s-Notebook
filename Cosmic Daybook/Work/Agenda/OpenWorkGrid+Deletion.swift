// OpenWorkGrid+Deletion.swift
// Which records a card's menu acts on, and what deleting them costs.
//
// Split from the grid so the view stays about layout. The message is the part
// worth writing carefully: `WorkModel.unifiedNotes` cascades, so the
// observations written against a work item go with it, and a guide clearing out
// stale cards should not find that out afterwards.

import CoreData
import SwiftUI

extension OpenWorkGrid {

    /// Which records a card's menu acts on: itself, or the whole selection when
    /// it is part of one. Resolved here because the grid is the only thing
    /// holding the other cards.
    func menuTargets(for work: CDWorkModel) -> [CDWorkModel] {
        guard let selection, let id = work.id,
              selection.contains(id), selection.count > 1 else {
            return [work]
        }
        return works.filter { selection.contains($0.id) }
    }

    var deletionTitle: String {
        pendingDeletion.count > 1
            ? "Delete \(pendingDeletion.count) work items?"
            : "Delete this work?"
    }

    var deletionConfirmTitle: String {
        pendingDeletion.count > 1 ? "Delete \(pendingDeletion.count) Items" : "Delete"
    }

    /// Says the part that isn't obvious: the notes go with the work — its own,
    /// its check-ins' and its completion records' (`WorkDeletionService.cascade`).
    /// A guide clearing out stale work should not have to discover that afterwards.
    var deletionMessage: String {
        let service = WorkDeletionService(context: viewContext)
        let cascade = pendingDeletion.reduce(WorkCascade()) { $0 + service.cascade(for: $1) }
        let isMany = pendingDeletion.count > 1
        let subject = isMany ? "These work items" : "This work"
        var costs: [String] = []
        if cascade.observations > 0 {
            costs.append("\(cascade.observations) " + (cascade.observations == 1 ? "observation" : "observations"))
        }
        if cascade.checkIns > 0 {
            costs.append("\(cascade.checkIns) " + (cascade.checkIns == 1 ? "check-in" : "check-ins"))
        }
        if cascade.completionRecords > 0 {
            costs.append("\(cascade.completionRecords) completed-work "
                + (cascade.completionRecords == 1 ? "entry" : "entries"))
        }
        guard !costs.isEmpty else {
            return subject + " will be deleted for every child. This can't be undone."
        }
        let pronoun = isMany ? "them" : "it"
        return subject + " and the " + costs.joined(separator: ", ") + " on " + pronoun
            + " will be deleted for every child. This can't be undone."
    }

    /// Deletes the cards in one save through `WorkDeletionService`, which also
    /// strips the deleted owners from surviving linked copies and sweeps the
    /// records that key work by id string. A failed save is taken back and
    /// said so; each card used to be deleted and saved on its own, and a
    /// failure only reached the log (bug hunt 2026-10-12 #44). `confirmed` is
    /// what the dialog was shown for, handed over by the dialog itself (G1).
    func performPendingDeletion(_ confirmed: [CDWorkModel]) {
        let targets = confirmed.filter { !$0.isDeleted }
        pendingDeletion = []
        do {
            try WorkDeletionService(context: viewContext).delete(targets)
        } catch {
            ToastService.shared.showError(
                targets.count > 1
                    ? "Couldn't delete those work items. Nothing was changed. Try again."
                    : "Couldn't delete this work. Nothing was changed. Try again."
            )
            return
        }
        // Drop only what was destroyed. Right-clicking an unselected card while
        // a selection is live deletes that one card, and clearing the whole
        // selection here would silently throw the rest of it away.
        let deleted = Set(targets.compactMap(\.id))
        selection?.retain(Set(works.compactMap(\.id)).subtracting(deleted))
        onDeleted?()
    }
}
