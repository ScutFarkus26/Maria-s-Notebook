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
    static let keptOnRestoreEntityNames: Set<String> = ["ClassroomMembership"]

    /// Entity type names for progress reporting and error messages
    static func entityName(for type: NSManagedObject.Type) -> String {
        String(describing: type)
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
