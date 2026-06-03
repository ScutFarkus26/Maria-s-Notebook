import Foundation
import CoreData
import OSLog

// MARK: - Utility & Helper Methods

extension BackupService {
    private static let logger = Logger.backup

    // MARK: - Entity Fetch

    func fetchOne<T: NSManagedObject>(_ type: T.Type, id: UUID, using context: NSManagedObjectContext) throws -> T? {
        return try BackupFetchHelper.fetchOne(type, id: id, using: context)
    }

    // MARK: - Preferences (delegated to BackupPreferencesService)

    func buildPreferencesDTO() -> PreferencesDTO {
        BackupPreferencesService.buildPreferencesDTO()
    }

    func applyPreferencesDTO(_ dto: PreferencesDTO) {
        BackupPreferencesService.applyPreferencesDTO(dto)
    }

    // MARK: - Data Management

    /// Deletes all backup-managed entities from the persistent store(s).
    ///
    /// Uses context-level `delete(_:)` (not `NSBatchDeleteRequest`) — only the context-level
    /// path emits the change events that `NSPersistentCloudKitContainer` mirrors to CloudKit.
    /// `NSBatchDeleteRequest` writes straight to SQLite and CloudKit re-uploads stale records
    /// on the next sync, resurrecting just-deleted data.
    ///
    /// Returns the names of any entities that could not be cleared, so callers can surface
    /// them as warnings instead of swallowing them silently.
    @discardableResult
    func deleteAll(
        viewContext: NSManagedObjectContext,
        pageSize: Int = 500
    ) throws -> [String] {
        let model = viewContext.persistentStoreCoordinator?.managedObjectModel
        var failedEntities: [String] = []

        for type in BackupEntityRegistry.allTypes {
            let entityName = String(describing: type).replacingOccurrences(of: "CD", with: "")

            // Never clear a type the restore can't repopulate. These entities are
            // listed in allTypes for schema completeness but have no importer, so
            // deleting them in replace mode would permanently destroy data the
            // backup never captured (e.g. Stories, Book Club, Year Plan, Day Pads).
            guard !BackupEntityRegistry.notYetBackedUpEntityNames.contains(entityName) else { continue }

            // Skip types whose entity doesn't exist in the model (legacy renames, deprecations).
            guard model?.entitiesByName[entityName] != nil else { continue }

            do {
                try deletePagedForEntity(
                    entityName: entityName,
                    in: viewContext,
                    pageSize: pageSize
                )
            } catch {
                failedEntities.append(entityName)
                let desc = error.localizedDescription
                Self.logger.warning(
                    "Failed to clear \(entityName, privacy: .public) during replace: \(desc, privacy: .public)"
                )
            }
        }

        return failedEntities
    }

    /// Pages through every object of `entityName`, deleting each via the context so
    /// CloudKit mirroring sees the change. Saves and refreshes between pages to keep
    /// memory bounded on large datasets.
    private func deletePagedForEntity(
        entityName: String,
        in viewContext: NSManagedObjectContext,
        pageSize: Int
    ) throws {
        while true {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.fetchLimit = pageSize
            // includesPropertyValues=false fetches faults only — we just need IDs to delete.
            request.includesPropertyValues = false

            let page = try viewContext.fetch(request)
            if page.isEmpty { break }

            for object in page {
                viewContext.delete(object)
            }

            try viewContext.save()
            // Drop the deleted objects' faults out of memory before the next page.
            viewContext.refreshAllObjects()

            if page.count < pageSize { break }
        }
    }

    func deduplicatePayload(_ payload: BackupPayload) -> BackupPayload {
        BackupPayloadDeduplicator.deduplicate(payload)
    }
}
