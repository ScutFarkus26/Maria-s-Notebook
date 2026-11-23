// PresentationDetailViewModel+NotesAutosave.swift
// Debounced notes autosave and flush helpers for PresentationDetailViewModel.

import Foundation

extension PresentationDetailViewModel {

    // MARK: - Notes Autosave

    func scheduleNotesAutosave() {
        notesDirty = (notes != originalNotes)
        notesAutosaveTask?.cancel()

        guard notesDirty else { return }

        notesAutosaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(600)) // 0.6s debounce
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            lessonAssignment.notes = notes
            markNotesSaved(ifSaved: saveCoordinator.save(viewContext, reason: "Auto-saving notes"))
            PresentationDetailUtilities.notifyInboxRefresh()
        }
    }

    func flushNotesAutosaveIfNeeded() {
        notesAutosaveTask?.cancel()
        guard notesDirty else { return }

        lessonAssignment.notes = notes
        markNotesSaved(ifSaved: saveCoordinator.save(viewContext, reason: "Saving notes"))
        PresentationDetailUtilities.notifyInboxRefresh()
    }

    /// Forgets the notes were unsaved only when the save went through. After a
    /// failed one they stay marked, so closing the sheet (which flushes) tries
    /// again instead of leaving them behind.
    private func markNotesSaved(ifSaved saved: Bool) {
        guard saved else { return }
        originalNotes = notes
        notesDirty = false
    }
}
