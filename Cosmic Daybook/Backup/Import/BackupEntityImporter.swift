import Foundation
import CoreData
import OSLog

/// Imports backup rows into the database.
///
/// Every backed-up type is a `ModelRow`, restored by `importRows`
/// (`BackupEntityImporter+ModelRows.swift`); a Merge's lesson files keep the
/// file they have now (`BackupEntityImporter+LessonFiles.swift`).
enum BackupEntityImporter {
    private static let logger = Logger.backup

    /// Type alias for a function that looks up an already-stored entity by ID.
    ///
    /// Returns the pre-restore record with that ID, or nil when none exists.
    /// Importers populate whichever object comes back — the existing one or a
    /// freshly inserted one — so a merge restore updates records in place
    /// (records absent from the backup are left alone, and so are records
    /// changed here since the backup: `BackupRestoreRun.rows` holds back the
    /// rows whose stored record has a later `modifiedAt`). In replace mode the
    /// store has already been cleared, so the lookup returns nil and every
    /// record is inserted, but for the types a Replace updates in place: the
    /// names people set and the classroom share's records
    /// (`BackupEntityRegistry.updatedInPlaceOnReplaceEntityNames`).
    typealias ExistingLookup<T: NSManagedObject> = (UUID) throws -> T?

    // MARK: - Common Helpers

    /// Resolves the pre-restore record for `id`, or nil when it doesn't exist.
    /// A lookup failure is logged and treated as "not found", so the record is
    /// inserted rather than dropped.
    static func existingEntity<T: NSManagedObject>(
        id: UUID,
        existing: ExistingLookup<T>
    ) -> T? {
        do {
            return try existing(id)
        } catch {
            logger.warning("Failed to look up existing entity: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
