// QuickNoteViewModel+Saving.swift
// Choosing the note's children and saving the note.

import CoreData
import Foundation

extension QuickNoteViewModel {

    // MARK: - Choosing Children

    /// What a name-finder pass adds and suggests: matches not already chosen,
    /// leaving out every child she took off this note.
    func newMatches(from result: StudentMatchResult) -> (add: Set<UUID>, suggest: Set<UUID>) {
        let add = result.exact.union(result.autoSelect)
            .subtracting(selectedStudentIDs)
            .subtracting(removedStudentIDs)
        let suggest = result.fuzzy
            .subtracting(selectedStudentIDs)
            .subtracting(add)
            .subtracting(removedStudentIDs)
        return (add, suggest)
    }

    /// Sets the chosen children from a picker or a chip, remembering who she
    /// took off (so the name finder leaves them off) and forgetting that for
    /// anyone she put back.
    func setSelectedStudents(_ ids: Set<UUID>) {
        removedStudentIDs.formUnion(selectedStudentIDs.subtracting(ids))
        removedStudentIDs.subtract(ids)
        selectedStudentIDs = ids
    }

    func removeStudent(_ id: UUID) {
        setSelectedStudents(selectedStudentIDs.subtracting([id]))
    }

    func addStudent(_ id: UUID) {
        setSelectedStudents(selectedStudentIDs.union([id]))
        detectedCandidateIDs.remove(id)
    }

    // MARK: - Saving

    /// Whether closing the sheet now would throw away something she made.
    var hasUnsavedContent: Bool {
        !didSave && (!bodyText.trimmed().isEmpty || attachedImagePath != nil)
    }

    /// Saves the note, its student links and its photo, then tells the
    /// screens that list notes. Returns whether it saved.
    ///
    /// Until 2026-10-10 this made the note and said "Note saved" without
    /// saving: the view context doesn't autosave, so the note sat in memory
    /// until some unrelated save, and was gone if iOS ended the app first.
    /// On a failed save the new note is taken back out, so Save again makes
    /// one note, not two, and `saveErrorMessage` says what happened.
    @discardableResult
    func saveNote(viewContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator) -> Bool {
        let trimmed = bodyText.trimmed()
        guard !trimmed.isEmpty, !didSave else { return false }

        let scope: NoteScope
        if selectedStudentIDs.count == 1, let firstID = selectedStudentIDs.first {
            scope = .student(firstID)
        } else if selectedStudentIDs.count > 1 {
            scope = .students(selectedStudentIDs.sorted { $0.uuidString < $1.uuidString })
        } else {
            scope = .all
        }

        // Fetch CDStudentTrackEnrollmentEntity if selectedEnrollmentID is set
        var studentTrackEnrollment: CDStudentTrackEnrollmentEntity?
        if let enrollmentID = selectedEnrollmentID {
            studentTrackEnrollment = viewContext.object(CDStudentTrackEnrollmentEntity.self, id: enrollmentID)
        }

        // Fetch CDLesson if selectedLessonID is set
        var lesson: CDLesson?
        if let lessonID = selectedLessonID {
            lesson = viewContext.object(CDLesson.self, id: lessonID)
        }

        let newNote = CDNote(context: viewContext)
        newNote.createdAt = noteDate
        newNote.body = trimmed
        newNote.scope = scope
        newNote.tags = tags as NSArray
        newNote.includeInReport = includeInReport
        newNote.needsFollowUp = needsFollowUp
        newNote.lesson = lesson
        newNote.studentTrackEnrollment = studentTrackEnrollment
        newNote.imagePath = attachedImagePath
        // A note about several children is found on their Notes tabs by its links.
        newNote.syncStudentLinks(in: viewContext)

        // The alert on this sheet says what failed, so the global one stays quiet.
        guard saveCoordinator.save(viewContext, reason: "Saving a quick note", alertOnFailure: false) else {
            for link in (newNote.studentLinks?.allObjects as? [CDNoteStudentLink]) ?? [] {
                viewContext.delete(link)
            }
            viewContext.delete(newNote)
            saveErrorMessage = saveCoordinator.lastSaveErrorMessage ?? Self.notSavedMessage
            return false
        }
        didSave = true
        NotificationCenter.default.post(name: .noteDidSave, object: newNote.id)
        ToastService.shared.show("Note saved", type: .success, duration: 1.5)
        return true
    }

    static let notSavedMessage = "Couldn't save this note. Your text is still here, so try again."

    /// Deletes a photo she attached but didn't save with a note, when she
    /// discards the note. A saved note keeps its photo.
    func discardUnsavedPhoto() {
        guard !didSave else { return }
        selectedPhotoItem = nil
        removeAttachedPhoto()
    }
}
