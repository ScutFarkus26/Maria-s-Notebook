import Foundation
import SwiftData

// MARK: - Batch Operations

extension StudentNotesViewModel {

    func fetchNote(id: UUID) -> Note? {
        let d = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.id == id }
        )
        return modelContext.safeFetchFirst(d)
    }

    func note(by id: UUID) -> Note? {
        fetchNote(id: id)
    }

    func batchDelete(ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                note.deleteAssociatedImage()
                modelContext.delete(note)
            }
        }
        if saveCoordinator.save(modelContext, reason: "Batch deleting notes") {
            items.removeAll { ids.contains($0.id) }
        }
    }

    func batchAddTags(_ tagsToAdd: [String], for ids: Set<UUID>) {
        for id in ids {
            if let note = fetchNote(id: id) {
                var current = note.tags
                for tag in tagsToAdd where !current.contains(tag) {
                    current.append(tag)
                }
                note.tags = current
                note.updatedAt = Date()
            }
        }
        if saveCoordinator.save(modelContext, reason: "Adding tags to notes") {
            fetchAllNotes()
        }
    }

    func batchRemoveTags(_ tagsToRemove: [String], for ids: Set<UUID>) {
        let removeSet = Set(tagsToRemove)
        for id in ids {
            if let note = fetchNote(id: id) {
                note.tags = note.tags.filter { !removeSet.contains($0) }
                note.updatedAt = Date()
            }
        }
        if saveCoordinator.save(modelContext, reason: "Removing tags from notes") {
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
        if saveCoordinator.save(modelContext, reason: "Toggling follow-up flags") {
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
        if saveCoordinator.save(modelContext, reason: "Toggling report flags") {
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
        if saveCoordinator.save(modelContext, reason: "Toggling pin status") {
            fetchAllNotes()
        }
    }
}
