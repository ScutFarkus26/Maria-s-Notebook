import Foundation
import CoreData
import OSLog

/// One-shot backfill of `CDNote.attendanceRecordID` from the still-present
/// `attendanceRecord` relationship.
///
/// **Why this exists.** Attendance is moving into the shared store so an
/// assistant's device can write it, but `Note` stays private — and a Core Data
/// relationship cannot cross store configurations. The link is therefore
/// converting to the repo's string-FK convention in two steps: this backfill
/// populates the FK while the relationship still exists, and a later build
/// deletes the relationship once every device has run it.
///
/// **Idempotent.** Only touches notes with a relationship target and no FK yet,
/// so re-running is a no-op; UserDefaults-gated so it normally runs once. New
/// links written after this build keep both sides in lockstep at the write site
/// (`setLegacyNoteText`), so nothing drifts between backfill and cutover.
enum AttendanceNoteLinkBackfill {

    private static let completedKey = UserDefaultsKeys.attendanceNoteLinkBackfillV1Complete
    private static let logger = Logger.migration

    /// Whether the backfill has already completed on this device.
    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    /// Runs the backfill on a background context unless it has already completed.
    @MainActor
    static func runIfNeeded(coreDataStack: CoreDataStack) async {
        guard !hasCompleted else { return }
        let context = coreDataStack.newBackgroundContext()
        await context.perform {
            run(in: context)
        }
    }

    /// The actual backfill, callable directly from tests with any context.
    /// Sets the completion flag only when the pass saves cleanly (or had
    /// nothing to do), so a failed save retries on the next launch.
    static func run(in context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "attendanceRecord != nil AND attendanceRecordID == nil"
        )
        let linked: [CDNote]
        do {
            linked = try context.fetch(request)
        } catch {
            logger.warning("Attendance note-link backfill fetch failed: \(error.localizedDescription)")
            return
        }

        guard !linked.isEmpty else {
            logger.info("Attendance note-link backfill: nothing to do")
            UserDefaults.standard.set(true, forKey: completedKey)
            return
        }

        var filled = 0
        for note in linked {
            guard let recordID = note.attendanceRecord?.id?.uuidString else { continue }
            note.attendanceRecordID = recordID
            filled += 1
        }

        guard context.safeSave() else {
            logger.warning("Attendance note-link backfill save failed; will retry next launch")
            return
        }
        logger.info("Attendance note-link backfill filled \(filled) of \(linked.count) notes")
        UserDefaults.standard.set(true, forKey: completedKey)
    }
}
