import Foundation
import SwiftData
import os

// MARK: - Note Repair

extension DataCleanupService {

    // MARK: - Note Cleanup

    /// Repair scope for notes that were incorrectly set to .all due to UI bugs.
    /// Specifically targets Attendance, WorkCompletion, and StudentMeeting notes.
    static func repairScopeForContextualNotes(using context: ModelContext) async {
        let flagKey = "Repair.noteScopes.v1"
        MigrationFlag.runIfNeeded(key: flagKey) {
            let notes = context.safeFetch(FetchDescriptor<Note>())
            var changed = 0

            for note in notes {
                var targetStudentID: UUID?

                if let rec = note.attendanceRecord, let uuid = UUID(uuidString: rec.studentID) {
                    targetStudentID = uuid
                } else if let rec = note.workCompletionRecord, let uuid = UUID(uuidString: rec.studentID) {
                    targetStudentID = uuid
                } else if let meeting = note.studentMeeting, let uuid = UUID(uuidString: meeting.studentID) {
                    targetStudentID = uuid
                }

                if let targetID = targetStudentID {
                    var needsFix = true
                    if case .student(let currentID) = note.scope {
                        if currentID == targetID { needsFix = false }
                    }
                    if needsFix {
                        note.scope = .student(targetID)
                        changed += 1
                    }
                }
            }

            if changed > 0 {
                context.safeSave()
            }
        }
    }

    /// Clean up orphaned note images that are no longer referenced by any Note.
    /// This should be run after note deletions to reclaim disk space.
    static func cleanupOrphanedNoteImages(using context: ModelContext) {
        do {
            let photosDir = try PhotoStorageService.photosDirectory()
            let fm = FileManager.default

            // Get all files in the Note Photos directory
            let files = try fm.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil)
            let imageFilenames = Set(files.map { $0.lastPathComponent })

            // Get all image paths referenced by notes
            let notesFetch = FetchDescriptor<Note>()
            let notes = context.safeFetch(notesFetch)
            let referencedPaths = Set(notes.compactMap { $0.imagePath })

            // Find orphaned files
            let orphanedFiles = imageFilenames.subtracting(referencedPaths)

            for filename in orphanedFiles {
                do {
                    try PhotoStorageService.deleteImage(filename: filename)
                } catch {
                    logger.warning("Failed to delete orphaned image \(filename, privacy: .public): \(error.localizedDescription)")
                }
            }
        } catch {
            logger.warning("Failed to cleanup orphaned images: \(error.localizedDescription)")
        }
    }

    /// Create NoteStudentLink records for existing notes with multi-student scope.
    /// This enables efficient database-level queries instead of in-memory filtering.
    static func createNoteStudentLinksForExistingNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { note in
                note.scopeIsAll == false && note.searchIndexStudentID == nil
            }
        )
        let notes = context.safeFetch(fetch)

        var createdCount = 0

        for note in notes {
            // Skip if links already exist
            guard (note.studentLinks ?? []).isEmpty else { continue }

            // Sync the student links based on current scope
            note.syncStudentLinks(in: context)

            if !(note.studentLinks ?? []).isEmpty {
                createdCount += 1
            }
        }

        if createdCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - Denormalized Field Repair

    /// Repairs denormalized scheduledForDay fields to match scheduledFor.
    /// This ensures data integrity when scheduledForDay gets out of sync with scheduledFor
    /// (e.g., during bulk imports or when didSet doesn't fire during initialization).
    /// Safe to call repeatedly - it's idempotent and only fixes mismatched records.
    static func repairDenormalizedScheduledForDay(using context: ModelContext) async {
        let fetch = FetchDescriptor<LessonAssignment>()
        let assignments = context.safeFetch(fetch)
        var repaired = 0

        for (index, la) in assignments.enumerated() {
            if index % 100 == 0 { await Task.yield() }

            let correct = la.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
            if la.scheduledForDay != correct {
                la.scheduledForDay = correct
                repaired += 1
            }
        }

        if repaired > 0 {
            context.safeSave()
        }
    }
}
