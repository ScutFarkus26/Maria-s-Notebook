import CoreData
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
    /// again (the save alert says what happened). After the save a moved
    /// lesson's tracks follow it, and a Pages file the form replaced or
    /// removed goes to the Trash when nothing else uses it.
    func saveEdits() {
        let onDisk = LessonEditDraft(lesson: lesson)
        let replacedPagesPath = draft.pagesFileChange == .unchanged
            ? nil : LessonFileStorage.managedPagesPath(of: lesson)
        let applied: Bool
        do {
            applied = try draft.apply(to: lesson)
        } catch {
            // A name its sub-area already has: nothing was written, and the
            // form stays open with her text so she can choose another.
            saveRefusal = error.errorDescription
            return
        }
        guard applied else {
            Self.logger.warning("Edit draft belonged to another lesson; nothing saved")
            discardPendingPagesCopy()
            isEditing = false
            return
        }
        guard saveCoordinator.save(viewContext, reason: "Update lesson") else {
            onDisk.restore(lesson)
            return
        }
        if draft.pagesFileChange != .unchanged {
            resolvedPagesURL = resolveLessonFileURL()
            if let replacedPagesPath, replacedPagesPath != lesson.pagesFileRelativePath {
                LessonFileStorage.trashUnreferencedFiles(
                    [replacedPagesPath], in: viewContext, isSampleClassroom: isSampleClassroom
                )
            }
            draft.pagesFileChange = .unchanged
        }
        isEditing = false
        onSave?(lesson)
    }

    /// Cancel in the form: nothing the form changed reaches the lesson, and
    /// a Pages file copied in by Import… is deleted again.
    func cancelEdits() {
        discardPendingPagesCopy()
        isEditing = false
    }

    /// Deletes the copy Import… made that Save never used.
    func discardPendingPagesCopy() {
        guard let url = draft.pendingPagesCopyURL else { return }
        draft.pagesFileChange = .unchanged
        do {
            try LessonFileStorage.deleteIfManaged(url)
        } catch {
            Self.logger.warning("Couldn't delete an unused Pages file copy: \(error)")
        }
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
