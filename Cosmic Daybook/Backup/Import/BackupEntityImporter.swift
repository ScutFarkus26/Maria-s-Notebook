import Foundation
import CoreData
import OSLog

/// Handles importing entities from backup DTOs into the database.
///
/// This extracts the entity import logic from BackupService for better
/// testability and separation of concerns.
///
/// Domain-specific import methods are organized into extensions:
/// - `BackupEntityImporter+Students.swift` -- student imports
/// - `BackupEntityImporter+Lessons.swift` -- lesson imports
/// - `BackupEntityImporter+Work.swift` -- work imports
/// - `BackupEntityImporter+Projects.swift` -- project imports
/// - `BackupEntityImporter+Calendar.swift` -- calendar imports
/// - `BackupEntityImporter+Todo.swift` -- todo imports
/// - `BackupEntityImporter+Misc.swift` -- misc entity imports
enum BackupEntityImporter {
    private static let logger = Logger.backup

    /// Type alias for a function that looks up an already-stored entity by ID.
    ///
    /// Returns the pre-restore record with that ID, or nil when none exists.
    /// Importers populate whichever object comes back — the existing one or a
    /// freshly inserted one — so a merge restore updates records in place
    /// (backup wins for any ID present in the backup; records absent from the
    /// backup are left alone). In replace mode the store has already been
    /// cleared, so the lookup always returns nil and every record is inserted.
    typealias ExistingLookup<T: NSManagedObject> = (UUID) throws -> T?

    /// Type alias for a function that resolves a relationship target by ID.
    ///
    /// Distinct from `ExistingLookup` on purpose: these callers assign the
    /// result to a relationship, so they need the object — and they're backed by
    /// `BackupEntityIndex.related`, which must see records inserted earlier in
    /// this same restore.
    typealias EntityLookup<T: NSManagedObject> = (UUID) throws -> T?

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

    /// Generic helper for importing simple entities with common pattern.
    ///
    /// `entityBuilder` receives the pre-restore record for the DTO's ID (or nil)
    /// and must populate and return either that object or a new one.
    static func importSimpleEntities<DTO, Entity: NSManagedObject>(
        _ dtos: [DTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<Entity>,
        idExtractor: (DTO) -> UUID,
        entityBuilder: (DTO, Entity?) -> Entity
    ) rethrows {
        for dto in dtos {
            let current = existingEntity(id: idExtractor(dto), existing: existing)
            let entity = entityBuilder(dto, current)
            viewContext.insert(entity)
        }
    }
}
