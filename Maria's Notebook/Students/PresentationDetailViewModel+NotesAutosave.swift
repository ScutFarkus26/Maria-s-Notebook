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

            await MainActor.run {
                lessonAssignment.notes = notes
                saveCoordinator.save(viewContext, reason: "Auto-saving notes")

                originalNotes = notes
                notesDirty = false
                PresentationDetailUtilities.notifyInboxRefresh()
            }
        }
    }

    func flushNotesAutosaveIfNeeded() {
        notesAutosaveTask?.cancel()
        guard notesDirty else { return }

        lessonAssignment.notes = notes
        saveCoordinator.save(viewContext, reason: "Saving notes")

        originalNotes = notes
        notesDirty = false
        PresentationDetailUtilities.notifyInboxRefresh()
    }
}
