import Foundation
import SwiftData

/// Handles importing entities from backup DTOs into the database.
///
/// This extracts the entity import logic from BackupService for better
/// testability and separation of concerns.
///
/// Domain-specific import methods are organized into extensions:
/// - `BackupEntityImporter+Students.swift` — student imports
/// - `BackupEntityImporter+Lessons.swift` — lesson, lesson assignment, lesson exercise, lesson attachment, lesson presentation imports
/// - `BackupEntityImporter+Work.swift` — work completion record, work check-in, work step, work participant, practice session imports
/// - `BackupEntityImporter+Projects.swift` — project, project role, project template week, project assignment template, project week role assignment, project session imports
/// - `BackupEntityImporter+Calendar.swift` — student meeting, attendance record, meeting template, reminder, calendar event imports
/// - `BackupEntityImporter+Todo.swift` — todo item, todo subtask, todo template, today agenda order imports
/// - `BackupEntityImporter+Misc.swift` — notes, note templates, non-school days, school day overrides, community topics, proposed solutions, community attachments, tracks, track steps, student track enrollments, group tracks, documents, supplies, supply transactions, procedures, schedules, schedule slots, issues, issue actions, development snapshots
enum BackupEntityImporter {

    /// Type alias for a function that checks if an entity with a given ID exists
    typealias EntityExistsCheck<T: PersistentModel> = (UUID) throws -> T?

    // MARK: - Common Helpers

    /// Generic helper to check if an entity exists and skip if it does.
    /// Returns true if the entity should be skipped (already exists).
    static func shouldSkipExisting<T: PersistentModel>(
        id: UUID,
        existingCheck: EntityExistsCheck<T>
    ) -> Bool {
        do {
            return try existingCheck(id) != nil
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to check if entity exists: \(error)")
            return false
        }
    }

    /// Generic helper for importing simple entities with common pattern.
    static func importSimpleEntities<DTO, Entity: PersistentModel>(
        _ dtos: [DTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Entity>,
        idExtractor: (DTO) -> UUID,
        entityBuilder: (DTO) -> Entity
    ) rethrows {
        for dto in dtos {
            let id = idExtractor(dto)
            if shouldSkipExisting(id: id, existingCheck: existingCheck) { continue }
            let entity = entityBuilder(dto)
            modelContext.insert(entity)
        }
    }
}
