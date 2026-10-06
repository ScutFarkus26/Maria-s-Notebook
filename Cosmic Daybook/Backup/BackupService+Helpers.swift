import Foundation
import CoreData
import OSLog

// MARK: - Utility & Helper Methods

extension BackupService {
    private static let logger = Logger.backup

    // MARK: - Preferences (delegated to BackupPreferencesService)

    func buildPreferencesDTO() -> PreferencesDTO {
        #if DEBUG
        // A test's fixed settings, when it bound some (see BackupPipelineRecorder).
        if let preferences = BackupPipelineRecorder.current?.preferences { return preferences }
        #endif
        return BackupPreferencesService.buildPreferencesDTO()
    }

    func applyPreferencesDTO(_ dto: PreferencesDTO) {
        BackupPreferencesService.applyPreferencesDTO(dto)
    }

    // MARK: - Data Management

    /// Marks every backup-managed record in the restore's store for deletion
    /// (`BackupRestoreScope`: the private store when there are two — a
    /// classroom someone else shared into the shared store isn't this
    /// notebook's to clear).
    ///
    /// Uses context-level `delete(_:)` (not `NSBatchDeleteRequest`) — only the context-level
    /// path emits the change events that `NSPersistentCloudKitContainer` mirrors to CloudKit.
    /// `NSBatchDeleteRequest` writes straight to SQLite and CloudKit re-uploads stale records
    /// on the next sync, resurrecting just-deleted data.
    ///
    /// Nothing is saved here: the deletes are saved with the import, in the
    /// restore's one save, so a restore that fails before then leaves the
    /// notebook exactly as it was. (Until 2026-10-05 each page was saved as
    /// it was cleared, so a failure part-way left an emptied notebook for the
    /// checkpoint to rebuild record by record.)
    ///
    /// Returns the names of any entities that could not be cleared, so callers can surface
    /// them as warnings instead of swallowing them silently.
    @discardableResult
    func deleteAll(viewContext: NSManagedObjectContext) throws -> [String] {
        var failedEntities: [String] = []
        let store = BackupRestoreScope.privateStore(of: viewContext)

        for type in BackupEntityRegistry.allTypes {
            // Resolve the MODEL entity name by matching the managed-object class,
            // not by stripping "CD" from the Swift type name. Several classes are
            // @objc-renamed (e.g. CDCommunityTopicEntity -> model "CommunityTopic"),
            // so naive stripping produced names absent from the model — and those
            // types were then silently skipped here, leaving replace-mode restores
            // without clearing them.
            guard let entityName = BackupFetchHelper.entityName(for: type, in: viewContext) else {
                // Type isn't in the loaded model (legacy rename/deprecation) — nothing to clear.
                continue
            }

            // Never clear a type the restore can't repopulate. These entities are
            // listed in allTypes for schema completeness but have no importer, so
            // deleting them in replace mode would permanently destroy data the
            // backup never captured.
            guard !BackupEntityRegistry.notYetBackedUpEntityNames.contains(entityName) else { continue }
            // Nor one the restore leaves alone on purpose (this device's pin).
            guard !BackupEntityRegistry.keptOnRestoreEntityNames.contains(entityName) else { continue }

            do {
                try deleteEvery(entityName, in: viewContext, store: store)
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

    /// Deletes every record of `entityName` in `store` (every store when nil)
    /// through the context, so CloudKit mirroring sees each delete once it is
    /// saved. Reads object IDs only: no record is loaded to be deleted, beyond
    /// what its delete rules need.
    private func deleteEvery(
        _ entityName: String,
        in viewContext: NSManagedObjectContext,
        store: NSPersistentStore?
    ) throws {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
        request.resultType = .managedObjectIDResultType
        if let store { request.affectedStores = [store] }
        for objectID in try viewContext.fetch(request) {
            viewContext.delete(viewContext.object(with: objectID))
        }
    }
}
