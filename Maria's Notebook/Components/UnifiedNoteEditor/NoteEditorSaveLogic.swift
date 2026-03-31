// NoteEditorSaveLogic.swift
// Save logic for UnifiedNoteEditor - extracted for maintainability

import OSLog
import SwiftUI
import CoreData

// MARK: - UnifiedNoteEditor Save Logic Extension

extension UnifiedNoteEditor {
    private static var logger: Logger { Logger.notes }

    /// Saves the note with proper context-specific relationships
    func saveNote() {
        let trimmedBody = bodyText.trimmed()
        guard !trimmedBody.isEmpty else { return }

        let scope = determineScope()

        let note: CDNote
        if let existing = initialNote {
            note = updateExistingNote(existing, body: trimmedBody, scope: scope)
        } else {
            note = createNewNote(body: trimmedBody, scope: scope)
        }

        do {
            try viewContext.save()
        } catch {
            Self.logger.error("Failed to save note: \(error.localizedDescription)")
        }
        onSave(note)
        dismiss()
    }

    // MARK: - Private Helpers

    private func determineScope() -> NoteScope {
        if selectedStudentIDs.isEmpty {
            return .all
        } else if selectedStudentIDs.count == 1, let first = selectedStudentIDs.first {
            return .student(first)
        } else {
            return .students(Array(selectedStudentIDs))
        }
    }

    private func updateExistingNote(_ existing: CDNote, body: String, scope: NoteScope) -> CDNote {
        // Clean up old image if it changed
        if let oldPath = originalImagePath,
           !oldPath.isEmpty,
           oldPath != imagePath {
            do {
                try PhotoStorageService.deleteImage(filename: oldPath)
            } catch {
                Self.logger.error("Failed to delete old image: \(error.localizedDescription)")
            }
        }

        existing.body = body
        existing.tags = tags as NSObject
        existing.includeInReport = includeInReport
        existing.needsFollowUp = needsFollowUp
        existing.imagePath = imagePath
        existing.updatedAt = Date()
        existing.scope = scope

        return existing
    }

    private func createNewNote(body: String, scope: NoteScope) -> CDNote {
        let note = CDNote(context: viewContext)
        note.body = body
        note.scope = scope
        note.tags = tags as NSObject
        note.includeInReport = includeInReport
        note.needsFollowUp = needsFollowUp
        note.imagePath = imagePath

        applyContextRelationship(to: note)

        return note
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func applyContextRelationship(to note: CDNote) {
        switch context {
        case .lesson(let lesson):
            note.lesson = lesson

        case .work(let work):
            note.work = work

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

        case .goingOut(let goingOut):
            note.goingOut = goingOut

        case .transitionPlan(let plan):
            note.transitionPlan = plan

        case .general:
            break
        }
    }
}
