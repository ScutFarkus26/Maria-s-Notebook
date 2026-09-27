import Foundation
import CoreData
import os

// MARK: - Note & Data Integrity Repairs

nonisolated extension DataCleanupService {

    // MARK: - Note Cleanup

    /// Clean up orphaned note images that are no longer referenced by any Note.
    ///
    /// **Local folder only.** The iCloud photo folder is shared by every device,
    /// and a photo reaches it through iCloud Drive before its note arrives
    /// through CloudKit (and on a newly set-up device, long before the first
    /// import finishes). Judged from one device's store, every such photo looks
    /// orphaned, and deleting it there would delete it on all devices. Photos in
    /// iCloud are removed only with their note (`CDNote.prepareForDeletion`) or
    /// by the editor that wrote them.
    static func cleanupOrphanedNoteImages(using context: NSManagedObjectContext) {
        do {
            let photosDir = try PhotoStorageService.localPhotosDirectory()
            let fm = FileManager.default

            let files = try fm.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil)
            let imageFilenames = Set(files.map(\.lastPathComponent))

            let notesFetch = CDFetchRequest(CDNote.self)
            let notes = context.safeFetch(notesFetch)
            let referencedPaths = Set(notes.compactMap(\.imagePath))

            let orphanedFiles = imageFilenames.subtracting(referencedPaths)

            for filename in orphanedFiles {
                do {
                    try PhotoStorageService.deleteLocalImage(filename: filename)
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
    ///
    /// Synchronous, on `context`'s queue: the launch pass runs it inside
    /// `perform` on a background context (see `MigrationRunner.runPass`).
    static func repairScheduledForDayMirror(using context: NSManagedObjectContext) {
        let fetch = CDFetchRequest(CDLessonAssignment.self)
        let assignments = context.safeFetch(fetch)
        var repaired = 0

        for la in assignments {
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
