// WorkDetailViewModel+Actions.swift
// The sheet's Save and Delete. A failure says so in a toast and leaves the
// sheet open, rather than closing as if it had worked.

import CoreData
import OSLog

extension WorkDetailViewModel {

    /// Returns false when nothing was saved, so the sheet stays open for
    /// another try. A failed status change says so in a toast (the log
    /// service keeps the global alert quiet); a failed plain save has the
    /// global alert.
    @discardableResult
    func save(modelContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator) -> Bool {
        guard let work else { return true }

        work.kind = workKind
        work.title = workTitle
        work.checkInStyle = checkInStyle

        // A status change is a log entry — completion record, check-ins, note —
        // so it goes the same way the Scheduled strip's does. The note field
        // used to be bound here and never written anywhere.
        let note = completionNote.trimmed()
        do {
            if status != work.status {
                try WorkLogService.log(
                    [.init(work: work, status: status, note: note.isEmpty ? nil : note)],
                    context: modelContext, saveCoordinator: saveCoordinator
                )
            } else {
                if !note.isEmpty {
                    WorkLogService.addNote(note, to: work, on: Date(), in: modelContext)
                }
                guard saveCoordinator.save(modelContext, reason: "Save work details") else { return false }
            }
            completionNote = ""
            return true
        } catch {
            ToastService.shared.showError(PresentationFailureMessage.message(
                for: error, fallback: "Couldn't save this work. Try again."
            ))
            return false
        }
    }

    func deleteWork(
        modelContext: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator,
        onDeleted: @escaping () -> Void
    ) {
        guard let work else { return }
        do {
            // The toast below reports a failure, so the global alert stays quiet.
            try WorkDeletionService(context: modelContext).delete([work]) {
                saveCoordinator.save(modelContext, reason: "Delete work", alertOnFailure: false)
            }
        } catch {
            Logger.work.error("Failed to delete work: \(error, privacy: .public)")
            ToastService.shared.showError("Couldn't delete this work. Nothing was changed. Try again.")
            return
        }
        onDeleted()
    }
}
