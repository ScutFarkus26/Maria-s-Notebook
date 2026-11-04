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

        // Only the fields the guide changed in this sitting are written. The
        // page read the row once, so writing every field put back whatever a
        // status or title set elsewhere since (the grid, Claude, another
        // device) had replaced: a Mastered set from the grid was reopened by
        // a Save with a note (bug hunt 2026-11-03 #33).
        let titleChanged = workTitle != storedTitle
        let kindChanged = workKind != storedKind

        // A new title or kind is the guide renaming the assignment, so it goes
        // on every linked copy. Renaming one copy used to leave the others
        // behind, and the copies stopped reading as one group. The group is
        // resolved before the edit, while every copy still matches.
        let rows = titleChanged || kindChanged
            ? WorkGrouping.group(containing: work, in: modelContext).members
            : [work]
        for row in rows {
            if kindChanged { row.kind = workKind }
            if titleChanged { row.title = workTitle }
        }
        if checkInStyle != storedCheckInStyle {
            work.checkInStyle = checkInStyle
        }

        // A status change is a log entry — completion record, check-ins, note —
        // so it goes the same way the Scheduled strip's does. The note field
        // used to be bound here and never written anywhere.
        let note = completionNote.trimmed()
        do {
            if status != storedStatus, status != work.status {
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
            rememberStored(from: work)
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
