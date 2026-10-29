// NoteEditorSaveLogic.swift
// Save logic for UnifiedNoteEditor - extracted for maintainability

import OSLog
import SwiftUI
import CoreData

// MARK: - UnifiedNoteEditor Save Logic Extension

extension UnifiedNoteEditor {

    /// Saves the note with proper context-specific relationships. The sheet
    /// closes only once the note is saved; a failed save keeps it open with
    /// `saveErrorMessage` (it used to close as if saved).
    func saveNote() {
        let trimmedBody = bodyText.trimmed()
        guard !trimmedBody.isEmpty else { return }

        let fields = NoteEditorSave.Fields(
            body: trimmedBody,
            tags: tags,
            includeInReport: includeInReport,
            needsFollowUp: needsFollowUp,
            imagePath: imagePath,
            scope: determineScope()
        )
        let target: NoteEditorSave.Target = initialNote.map {
            .existing($0, originalImagePath: originalImagePath)
        } ?? .new(attach: { applyContextRelationship(to: $0) })
        let outcome = NoteEditorSave.save(
            fields, to: target, in: viewContext, saveCoordinator: dependencies.saveCoordinator
        )
        switch outcome {
        case .saved(let note):
            onSave(note)
            dismiss()
        case .failed(let message):
            saveErrorMessage = message
        }
    }

    /// Whether closing now would throw away anything Save writes: the text,
    /// photo, children, tags, "Include in report" or "Needs follow-up" (bug
    /// hunt 2026-10-29, #21: it used to look only at the text and photo).
    var hasUnsavedChanges: Bool {
        guard let openedEdit else { return false }
        return currentEdit != openedEdit
    }

    /// What Save would write, as the editor holds it now.
    var currentEdit: NoteEditorSave.Edit {
        NoteEditorSave.Edit(
            body: bodyText,
            children: selectedStudentIDs,
            tags: tags,
            includeInReport: includeInReport,
            needsFollowUp: needsFollowUp,
            imagePath: imagePath
        )
    }

    /// Cancel: asks first when there are edits to lose.
    func requestCancel() {
        if hasUnsavedChanges {
            isConfirmingDiscard = true
        } else {
            discardAndClose()
        }
    }

    /// Closes without saving, deleting a photo attached in this editor that no
    /// saved note points at (the note's own photo stays).
    func discardAndClose() {
        NoteEditorSave.deleteUnsavedPhoto(imagePath, original: originalImagePath)
        onCancel()
        dismiss()
    }

    // MARK: - Private Helpers

    private func determineScope() -> NoteScope {
        NoteScope.forSelection(selectedStudentIDs, fallback: contextRoster)
    }

    /// The children a note with no explicit selection is about. A note
    /// written on a presentation is about the children who received it,
    /// never the whole class — `.all` would make it read as an observation
    /// of every child on the roster.
    private var contextRoster: [UUID] {
        switch context {
        case .presentation(let presentation):
            return presentation.resolvedStudentIDs
        default:
            return []
        }
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

        case .general:
            break
        }
    }
}

// MARK: - The Save Itself

/// The note editor's save, apart from the view so it can be tested.
enum NoteEditorSave {
    private static let logger = Logger.notes

    /// What the editor writes onto the note.
    struct Fields {
        var body: String
        var tags: [String]
        var includeInReport: Bool
        var needsFollowUp: Bool
        var imagePath: String?
        var scope: NoteScope
    }

    /// The note the editor saves into.
    enum Target {
        /// A note being edited, with the photo it had when the editor opened.
        case existing(CDNote, originalImagePath: String?)
        /// A new note; `attach` hangs it on the record it was written on.
        case new(attach: (CDNote) -> Void)
    }

    /// Everything the editor saves, to tell whether closing loses any of it.
    /// Text compares trimmed, as Save writes it.
    struct Edit: Equatable {
        var body: String
        var children: Set<UUID>
        var tags: [String]
        var includeInReport: Bool
        var needsFollowUp: Bool
        var imagePath: String?

        static func == (lhs: Edit, rhs: Edit) -> Bool {
            lhs.body.trimmed() == rhs.body.trimmed()
                && lhs.children == rhs.children
                && lhs.tags == rhs.tags
                && lhs.includeInReport == rhs.includeInReport
                && lhs.needsFollowUp == rhs.needsFollowUp
                && lhs.imagePath == rhs.imagePath
        }
    }

    enum Outcome {
        case saved(CDNote)
        /// Not saved; the message says so in plain words.
        case failed(String)
    }

    static let notSavedMessage = "Couldn't save this note. Your changes are still here, so try again."

    /// Writes `fields` onto the target note, keeps its student links in step
    /// with its scope (re-scoping used to leave the old links, and a new
    /// multi-child note had none), and saves.
    ///
    /// - The note's old photo is deleted only once the save has gone through:
    ///   deleted first, a failed save left the note pointing at a file that
    ///   was gone.
    /// - A save that fails takes back everything it changed
    ///   (`ContextMutationTransaction`): a new note is taken back out, so Save
    ///   again makes one note, not two, and an edited note goes back to its
    ///   text, scope, links and photo, so Discard Changes discards and no
    ///   later save writes the edit. The editor still holds her edits for the
    ///   retry. Other screens' unsaved changes are left alone.
    /// - A saved note is announced with `.noteDidSave`, which the note lists
    ///   reload on.
    static func save(
        _ fields: Fields,
        to target: Target,
        in context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) -> Outcome {
        let transaction = ContextMutationTransaction(context: context)
        let note: CDNote
        let originalImagePath: String?
        switch target {
        case .existing(let existing, let original):
            note = existing
            note.updatedAt = Date()
            originalImagePath = original
        case .new(let attach):
            note = CDNote(context: context)
            attach(note)
            originalImagePath = nil
        }
        note.body = fields.body
        note.tags = fields.tags as NSObject
        note.includeInReport = fields.includeInReport
        note.needsFollowUp = fields.needsFollowUp
        note.imagePath = fields.imagePath
        note.scope = fields.scope
        note.syncStudentLinks(in: context)

        // The editor shows what failed, so the global alert stays quiet.
        guard saveCoordinator.save(context, reason: "Saving a note", alertOnFailure: false) else {
            transaction.rollback()
            return .failed(saveCoordinator.lastSaveErrorMessage ?? notSavedMessage)
        }
        transaction.commit()

        if let oldPath = originalImagePath, !oldPath.isEmpty, oldPath != fields.imagePath {
            deletePhoto(oldPath)
        }
        NotificationCenter.default.post(name: .noteDidSave, object: note.id)
        return .saved(note)
    }

    /// What the plain note sheet (`NoteEditSheet`) changes: text, tags and flags.
    struct SheetEdit {
        var body: String
        var tags: [String]
        var includeInReport: Bool
        var isPinned: Bool
        var needsFollowUp: Bool
    }

    /// Writes the sheet's edit onto `note` and saves; on a failed save the
    /// note goes back to how it was, as `save(_:to:in:saveCoordinator:)` does.
    static func save(
        _ edit: SheetEdit, to note: CDNote, in context: NSManagedObjectContext, saveCoordinator: SaveCoordinator
    ) -> Outcome {
        let transaction = ContextMutationTransaction(context: context)
        note.body = edit.body
        note.tags = edit.tags as NSObject
        note.includeInReport = edit.includeInReport
        note.isPinned = edit.isPinned
        note.needsFollowUp = edit.needsFollowUp
        note.updatedAt = Date()
        // The sheet shows what failed, so the global alert stays quiet.
        guard saveCoordinator.save(context, reason: "Editing a note", alertOnFailure: false) else {
            transaction.rollback()
            return .failed(saveCoordinator.lastSaveErrorMessage ?? notSavedMessage)
        }
        transaction.commit()
        NotificationCenter.default.post(name: .noteDidSave, object: note.id)
        return .saved(note)
    }

    /// Deletes `path` when it is a photo attached in the editor that the note
    /// doesn't already own (`original`), when she closes without saving.
    static func deleteUnsavedPhoto(_ path: String?, original: String?) {
        guard let path, !path.isEmpty, path != original else { return }
        deletePhoto(path)
    }

    private static func deletePhoto(_ path: String) {
        do {
            try PhotoStorageService.deleteImage(filename: path)
        } catch {
            logger.error("Failed to delete a note photo: \(error.localizedDescription)")
        }
    }
}
