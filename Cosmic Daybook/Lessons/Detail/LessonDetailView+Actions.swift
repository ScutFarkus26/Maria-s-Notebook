import OSLog
import SwiftUI

// MARK: - Save and Delete

extension LessonDetailView {
    func close() {
        if let onDone { onDone() } else { dismiss() }
    }

    /// Writes the draft to this lesson and saves. A draft filled from another
    /// lesson is never written here. On a failed save the lesson goes back to
    /// what was on disk and the form stays open with her text, so she can try
    /// again (the save alert says what happened).
    func saveEdits() {
        let onDisk = LessonEditDraft(lesson: lesson)
        guard draft.apply(to: lesson) else {
            Self.logger.warning("Edit draft belonged to another lesson; nothing saved")
            isEditing = false
            return
        }
        guard saveCoordinator.save(viewContext, reason: "Update lesson") else {
            onDisk.restore(lesson)
            return
        }
        isEditing = false
        onSave?(lesson)
    }

    /// Asks first, naming what goes with the lesson (`LessonDeletion`).
    func confirmDelete() {
        guard let lessonID = lesson.id else { return }
        pendingDeletion = LessonDeletion.plan(for: lessonID, in: viewContext).summary
    }

    /// Deletes the lesson and what goes with it, recounted now in case sync
    /// brought more since the question. A failed save is rolled back whole;
    /// files go to the Trash only after it succeeds, and never in the Sample Class.
    func deleteLesson() {
        guard let lessonID = lesson.id else { return }
        let trashFiles: (([URL]) -> Void)?
        if isSampleClassroom {
            trashFiles = nil
        } else {
            trashFiles = { LessonFileStorage.moveToTrash($0) }
        }
        do {
            try repository.deleteLesson(id: lessonID, trashFiles: trashFiles)
        } catch {
            Self.logger.warning("Failed to delete lesson: \(error)")
            deleteError = "Couldn't delete this lesson. Try again."
            return
        }
        close()
    }
}
