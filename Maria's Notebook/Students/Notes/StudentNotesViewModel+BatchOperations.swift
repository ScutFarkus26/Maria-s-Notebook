import Foundation
import CoreData

// MARK: - Batch Operations

extension StudentNotesViewModel {

    func fetchNote(id: UUID) -> CDNote? {
        let d: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
        d.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return viewContext.safeFetchFirst(d)
    }

    func note(by id: UUID) -> CDNote? {
        fetchNote(id: id)
    }

    func batchDelete(ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                note.deleteAssociatedImage()
                viewContext.delete(note)
            }
        }
        if saveCoordinator.save(viewContext, reason: "Batch deleting notes") {
            items.removeAll { ids.contains($0.id) }
        }
    }

    func batchAddTags(_ tagsToAdd: [String], for ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                var current = note.tagsArray
                for tag in tagsToAdd where !current.contains(tag) {
                    current.append(tag)
                }
                note.tagsArray = current
                note.updatedAt = Date()
            }
        }
        if saveCoordinator.save(viewContext, reason: "Adding tags to notes") {
            fetchAllNotes()
        }
    }

    func batchRemoveTags(_ tagsToRemove: [String], for ids: Set<UUID>) {
        let removeSet = Set(tagsToRemove)
        for id in ids {
            if let note = fetchNote(id: id) {
                note.tagsArray = note.tagsArray.filter { !removeSet.contains($0) }
                note.updatedAt = Date()
            }
        }
        if saveCoordinator.save(viewContext, reason: "Removing tags from notes") {
            fetchAllNotes()
        }
    }

    func batchToggleFollowUp(for ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                note.needsFollowUp.toggle()
                note.updatedAt = Date()
            }
        }
        if saveCoordinator.save(viewContext, reason: "Toggling follow-up flags") {
            fetchAllNotes()
        }
    }

    func batchToggleReportFlag(for ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                note.includeInReport.toggle()
                note.updatedAt = Date()
            }
        }
        if saveCoordinator.save(viewContext, reason: "Toggling report flags") {
            fetchAllNotes()
        }
    }

    func batchTogglePin(for ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                note.isPinned.toggle()
                note.updatedAt = Date()
            }
        }
        if saveCoordinator.save(viewContext, reason: "Toggling pin status") {
            fetchAllNotes()
        }
    }
}
