// NoteEditorSaveLogic.swift
// Save logic for UnifiedNoteEditor - extracted for maintainability

import SwiftUI
import SwiftData

// MARK: - UnifiedNoteEditor Save Logic Extension

extension UnifiedNoteEditor {

    /// Saves the note with proper context-specific relationships
    func saveNote() {
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }

        let scope = determineScope()

        let note: Note
        if let existing = initialNote {
            note = updateExistingNote(existing, body: trimmedBody, scope: scope)
        } else {
            note = createNewNote(body: trimmedBody, scope: scope)
        }

        try? modelContext.save()
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
            try? PhotoStorageService.deleteImage(filename: oldPath)
        }

        existing.body = body
        existing.category = category
        existing.includeInReport = includeInReport
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
            category: category,
            includeInReport: includeInReport,
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
            note.studentLesson = sl

        case .presentation(let presentation):
            note.presentation = presentation
            if let legacyIDString = presentation.legacyStudentLessonID,
               let legacyID = UUID(uuidString: legacyIDString) {
                let descriptor = FetchDescriptor<StudentLesson>(
                    predicate: #Predicate { $0.id == legacyID }
                )
                if let studentLesson = try? modelContext.fetch(descriptor).first {
                    note.studentLesson = studentLesson
                }
            }

        case .attendance(let record):
            note.attendanceRecord = record

        case .workCheckIn(let checkIn):
            note.workCheckIn = checkIn

        case .workCompletion(let record):
            note.workCompletionRecord = record

        case .workPlanItem(let item):
            note.workPlanItem = item

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
