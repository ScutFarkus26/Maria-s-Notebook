import Foundation
import CoreData
import os

// MARK: - Note & Data Integrity Repairs

extension DataCleanupService {

    // MARK: - Note Cleanup

    /// Repair scope for notes that were incorrectly set to .all due to UI bugs.
    static func repairScopeForContextualNotes(using context: NSManagedObjectContext) async {
        let flagKey = "Repair.noteScopes.v1"
        MigrationFlag.runIfNeeded(key: flagKey) {
            let notes = context.safeFetch(CDFetchRequest(CDNote.self))
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
    static func cleanupOrphanedNoteImages(using context: NSManagedObjectContext) {
        do {
            let photosDir = try PhotoStorageService.photosDirectory()
            let fm = FileManager.default

            let files = try fm.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil)
            let imageFilenames = Set(files.map(\.lastPathComponent))

            let notesFetch = CDFetchRequest(CDNote.self)
            let notes = context.safeFetch(notesFetch)
            let referencedPaths = Set(notes.compactMap(\.imagePath))

            let orphanedFiles = imageFilenames.subtracting(referencedPaths)

            for filename in orphanedFiles {
                do {
                    try PhotoStorageService.deleteImage(filename: filename)
                } catch {
                    logger.warning(
                        "Failed to delete orphaned image \(filename, privacy: .public): \(error.localizedDescription)"
                    )
                }
            }
        } catch {
            logger.warning("Failed to cleanup orphaned images: \(error.localizedDescription)")
        }
    }

    // MARK: - Denormalized Field Repair

    /// Repairs the `scheduledForDay` mirror so it always equals start-of-day of
    /// `scheduledFor`. Runs at launch; idempotent.
    ///
    /// **It must never write `scheduledFor` itself.** It used to: it snapped the
    /// stored value to midnight to enforce a day-only model. `scheduledFor` now
    /// carries the lesson's position within its day (see
    /// `CDLessonAssignment.schedule(for:using:)`), so flattening it here would
    /// erase every guide's within-day ordering — on a random tenth of launches,
    /// then push the flattening to every device through CloudKit. This is the
    /// same mirror-only shape used after a restore in
    /// `BackupService+Restoration`.
    static func repairScheduledForDayMirror(using context: NSManagedObjectContext) async {
        let fetch = CDFetchRequest(CDLessonAssignment.self)
        let assignments = context.safeFetch(fetch)
        var repaired = 0

        for (index, la) in assignments.enumerated() {
            if index % 100 == 0 { await Task.yield() }

            let correctMirror = la.scheduledFor.map(AppCalendar.startOfDay) ?? Date.distantPast
            if la.scheduledForDay != correctMirror {
                la.scheduledForDay = correctMirror
                repaired += 1
            }
        }

        if repaired > 0 {
            context.safeSave()
        }
    }
}
