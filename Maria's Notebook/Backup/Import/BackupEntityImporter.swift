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

    /// Type alias for a function that checks if an entity with a given ID exists
    typealias EntityExistsCheck<T: NSManagedObject> = (UUID) throws -> T?

    // MARK: - Common Helpers

    /// Generic helper to check if an entity exists and skip if it does.
    /// Returns true if the entity should be skipped (already exists).
    static func shouldSkipExisting<T: NSManagedObject>(
        id: UUID,
        existingCheck: EntityExistsCheck<T>
    ) -> Bool {
        do {
            return try existingCheck(id) != nil
        } catch {
            logger.warning("Failed to check if entity exists: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Generic helper for importing simple entities with common pattern.
    static func importSimpleEntities<DTO, Entity: NSManagedObject>(
        _ dtos: [DTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<Entity>,
        idExtractor: (DTO) -> UUID,
        entityBuilder: (DTO) -> Entity
    ) rethrows {
        for dto in dtos {
            let id = idExtractor(dto)
            if shouldSkipExisting(id: id, existingCheck: existingCheck) { continue }
            let entity = entityBuilder(dto)
            viewContext.insert(entity)
        }
    }
}
