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

    /// Says the part that isn't obvious: `unifiedNotes` cascades, so the
    /// observations written against this work go with it. A guide clearing out
    /// stale work should not have to discover that afterwards.
    var deletionMessage: String {
        let observations = pendingDeletion.reduce(into: 0) { total, work in
            total += work.unifiedNotes?.count ?? 0
        }
        let isMany = pendingDeletion.count > 1
        let subject = isMany ? "These work items" : "This work"
        guard observations > 0 else {
            return subject + " will be removed from every child's record. This cannot be undone."
        }
        let noun = observations == 1 ? "observation" : "observations"
        let pronoun = isMany ? "them" : "it"
        return subject + " and the \(observations) " + noun + " written on " + pronoun
            + " will be removed from every child's record. This cannot be undone."
    }

    func performPendingDeletion() {
        let repository = WorkRepository(context: viewContext)
        for work in pendingDeletion {
            guard let id = work.id else { continue }
            repository.deleteWork(id: id)
        }
        // Drop only what was destroyed. Right-clicking an unselected card while
        // a selection is live deletes that one card, and clearing the whole
        // selection here would silently throw the rest of it away.
        let deleted = Set(pendingDeletion.compactMap(\.id))
        selection?.retain(Set(works.compactMap(\.id)).subtracting(deleted))
        pendingDeletion = []
        onDeleted?()
    }
}
