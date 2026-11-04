import Foundation
import CoreData

/// Centralized registry of all entity types that need to be backed up and restored.
/// This serves as the single source of truth to avoid hardcoding entity lists in multiple places.
struct BackupEntityRegistry {
    /// All entity types that are backed up, in archive order: `BackupEntityTable`'s.
    static let allTypes: [NSManagedObject.Type] = BackupEntityTable.entities.map { $0.managedType() }

    /// Entity types listed in `allTypes` for schema completeness but NOT yet
    /// round-tripped by the backup: they have no DTO transformer, no importer,
    /// and `BackupService+DataCollection` does not collect them.
    ///
    /// Replace-mode restore (`deleteAll`) MUST skip these — clearing a type the
    /// restore can't repopulate would permanently delete the user's data, and
    /// because the deletes emit CloudKit tombstones, propagate that loss to
    /// every device. Add a type here only while it lacks a DTO + importer; remove
    /// it once it round-trips so replace mode clears and restores it normally.
    ///
    /// Currently empty: every type in `allTypes` is fully backed up and restored
    /// (DayPad, YearPlanEntry, LessonSequenceSettings, Story, and Book Club were
    /// added to backup coverage in format v18).
    static let notYetBackedUpEntityNames: Set<String> = []

    /// Types a backup carries but a restore neither clears nor writes.
    ///
    /// `ClassroomMembership` rows say where *this device* stands in a CloudKit
    /// classroom share, pinned by zone name — and a zone exists only in the
    /// CloudKit environment and notebook that made it. Restored into the fresh
    /// Production notebook, a Development row would pin a share that isn't
    /// there; cleared by a Replace restore, the device would forget the share
    /// it really has. So restore leaves the device's own rows as they are.
    ///
    /// `CalendarEvent` rows are copies of the device's Apple Calendar
    /// (`EventKitMirror` is their only writer), matched to it by
    /// EventKit identifiers a backup leaves out. Restored, each came back as
    /// a copy no sync could match, so the next sync added the real one again
    /// beside it; cleared, the next sync wrote every one again. So restore
    /// leaves them as they are and the next sync brings them up to date.
    static let keptOnRestoreEntityNames: Set<String> = ["ClassroomMembership", "CalendarEvent"]

    /// Types a Replace restore updates as a Merge does, rather than clearing.
    ///
    /// `ClassroomPerson` rows are the names people in the classroom set for
    /// themselves, an assistant's written from her own phone. Cleared, a
    /// Replace put back each name as the backup had it, over a rename made
    /// since, and that old name then went to every device as the newest (bug
    /// hunt 2026-10-29). Left in place, the restore's newer-wins check
    /// (`BackupRestoreRun.keepingNewer`) keeps a rename, and a name set since
    /// the backup stays.
    static let mergedOnReplaceEntityNames: Set<String> = ["ClassroomPerson"]

    /// The classroom-share types (`CoreDataStack.sharedEntityNames`) a Replace
    /// restore updates in place by `id`, deleting only the records the backup
    /// lacks, rather than clearing them and inserting them again.
    ///
    /// On the lead guide's Mac these records live in the classroom share's
    /// zone. Cleared and inserted again, every one became a new record in the
    /// private default zone: one export deleted the whole class from iCloud,
    /// so the Assistant's phone emptied, and the copies reached the share only
    /// when the orphan guard filed them minutes later (bug hunt 2026-11-02,
    /// #2). Updated in place, each keeps its CloudKit identity and zone, and
    /// the Assistant sees edits rather than a wipe. The names people set are
    /// left out: a Replace merges them (`mergedOnReplaceEntityNames`).
    static let updatedInPlaceOnReplaceEntityNames: Set<String> =
        CoreDataStack.sharedEntityNames.subtracting(mergedOnReplaceEntityNames)

    /// Entity type names for progress reporting and error messages
    static func entityName(for type: NSManagedObject.Type) -> String {
        String(describing: type)
    }
}

nonisolated extension BackupEntity {
    /// Whether a backup of `formatVersion` can hold this type's records
    /// (`firstFormat`). One that can't has none of them, which says nothing
    /// about the notebook's: a Replace restore from it leaves them as they
    /// are, where clearing them emptied the type with nothing to put back (a
    /// v41 backup emptied Schedules; bug hunt 2026-10-29).
    func isCarried(by formatVersion: Int) -> Bool {
        formatVersion >= firstFormat
    }
}

/// Structured progress tracking for backup operations
struct BackupProgress {
    enum Phase: Double {
        case collecting = 0.0
        case encoding = 0.30
        case encrypting = 0.50
        case writing = 0.70
        case verifying = 0.90
        case complete = 1.0
    }
    
    /// Calculate progress percentage for a phase with optional sub-progress within that phase
    static func progress(for phase: Phase, subProgress: Double = 0.0) -> Double {
        let phaseStart = phase.rawValue
        let phaseEnd: Double
        switch phase {
        case .collecting: phaseEnd = Phase.encoding.rawValue
        case .encoding: phaseEnd = Phase.encrypting.rawValue
        case .encrypting: phaseEnd = Phase.writing.rawValue
        case .writing: phaseEnd = Phase.verifying.rawValue
        case .verifying: phaseEnd = Phase.complete.rawValue
        case .complete: return 1.0
        }
        let phaseRange = phaseEnd - phaseStart
        return phaseStart + (phaseRange * subProgress)
    }
}
