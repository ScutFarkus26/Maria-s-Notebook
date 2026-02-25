// NoteEditorSaveLogic.swift
// Save logic for UnifiedNoteEditor - extracted for maintainability

import OSLog
import SwiftUI
import SwiftData

// MARK: - UnifiedNoteEditor Save Logic Extension

extension UnifiedNoteEditor {
    private static var logger: Logger { Logger.notes }

    /// Saves the note with proper context-specific relationships
    func saveNote() {
        let trimmedBody = bodyText.trimmed()
        guard !trimmedBody.isEmpty else { return }

        let scope = determineScope()

        let note: Note
        if let existing = initialNote {
            note = updateExistingNote(existing, body: trimmedBody, scope: scope)
        } else {
            note = createNewNote(body: trimmedBody, scope: scope)
        }

        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to save note: \(error)")
        }
        onSave(note)
        dismiss()
    }

    // MARK: - Private Helpers

    private func determineScope() -> NoteScope {
        if selectedStudentIDs.isEmpty {
            return .all
        } else if selectedStudentIDs.count == 1 {
            return .student(selectedStudentIDs.first!)
        } else {
            return .students(Array(selectedStudentIDs))
        }
    }

    private func updateExistingNote(_ existing: Note, body: String, scope: NoteScope) -> Note {
        // Clean up old image if it changed
        if let oldPath = originalImagePath,
           !oldPath.isEmpty,
           oldPath != imagePath {
            do {
                try PhotoStorageService.deleteImage(filename: oldPath)
            } catch {
                print("⚠️ [\(#function)] Failed to delete old image: \(error)")
            }
        }

        existing.body = body
        existing.tags = tags
        existing.includeInReport = includeInReport
        existing.needsFollowUp = needsFollowUp
        existing.imagePath = imagePath
        existing.updatedAt = Date()
        existing.scope = scope

        // Sync student links atomically after scope change
        existing.syncStudentLinksIfNeeded(in: modelContext)

        return existing
    }

    private func createNewNote(body: String, scope: NoteScope) -> Note {
        let note = Note(
            body: body,
            scope: scope,
            tags: tags,
            includeInReport: includeInReport,
            needsFollowUp: needsFollowUp,
            imagePath: imagePath
        )

        applyContextRelationship(to: note)

        modelContext.insert(note)

        // Sync student links atomically after note creation
        note.syncStudentLinksIfNeeded(in: modelContext)

        return note
    }

    private func applyContextRelationship(to note: Note) {
        switch context {
        case .lesson(let lesson):
            note.lesson = lesson

        case .work(let work):
            note.work = work

        case .studentLesson(let sl):
            // Try to find the corresponding Presentation (new unified model)
            // to link the note to both for forward compatibility
            let slIDString = sl.id.uuidString
            let presentationDescriptor = FetchDescriptor<Presentation>(
                predicate: #Predicate { $0.migratedFromStudentLessonID == slIDString }
            )
            if let pres = modelContext.safeFetchFirst(presentationDescriptor) {
                // Prefer linking to Presentation for forward compatibility
                note.lessonAssignment = pres
            }
            // Also link to StudentLesson for backward compatibility
            note.studentLesson = sl

        case .presentation(let pres):
            note.lessonAssignment = pres

        case .attendance(let record):
            note.attendanceRecord = record

        case .workCheckIn(let checkIn):
            note.workCheckIn = checkIn

        case .workCompletion(let record):
            note.workCompletionRecord = record

        case .studentMeeting(let meeting):
            note.studentMeeting = meeting

        case .projectSession(let session):
            note.projectSession = session

        case .communityTopic(let topic):
            note.communityTopic = topic

        case .reminder(let reminder):
            note.reminder = reminder

        case .schoolDayOverride(let override):
            note.schoolDayOverride = override

        case .general:
            break
        }
    }
}
