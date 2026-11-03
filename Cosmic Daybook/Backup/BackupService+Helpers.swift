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
    /// Types a backup of `formatVersion` can't hold are left as they are
    /// (`BackupEntity.isCarried(by:)`), as are the names people set
    /// (`BackupEntityRegistry.mergedOnReplaceEntityNames`), the classroom-share
    /// types, which the restore updates in place
    /// (`deleteSharedRecordsTheBackupLacks`), and the `skipped` types, whose
    /// entry in the backup couldn't be read: it has nothing of them to put
    /// back (bug hunt 2026-11-02, #10).
    ///
    /// Returns the names of any entities that could not be cleared, so callers can surface
    /// them as warnings instead of swallowing them silently.
    @discardableResult
    func deleteAll(
        viewContext: NSManagedObjectContext, formatVersion: Int, skipped: Set<String> = []
    ) throws -> [String] {
        var failedEntities: [String] = []
        let store = BackupRestoreScope.privateStore(of: viewContext)

        for entity in BackupEntityTable.entities {
            let type = entity.managedType()
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
            // Nor one it updates in place (the names people set for themselves,
            // and the classroom share's records, which keep their zone).
            guard !BackupEntityRegistry.mergedOnReplaceEntityNames.contains(entityName),
                  !BackupEntityRegistry.updatedInPlaceOnReplaceEntityNames.contains(entityName) else { continue }
            // Nor one the backup is too old to hold, or whose entry it couldn't
            // read: it has none of them to put back, so clearing them would
            // only empty the type.
            guard entity.isCarried(by: formatVersion), !skipped.contains(entity.name) else { continue }

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

    /// A Replace's last step for the classroom-share types it updated in
    /// place: deletes each record in the restore's store whose `id` the
    /// backup lacks (`idsInBackup`, per type; a type with no entry there is
    /// left as it is). The records the backup holds were updated where they
    /// are, so on the lead guide's Mac they stay in the share's zone with
    /// their CloudKit identity (bug hunt 2026-11-02, #2). A record with no
    /// `id` is one the backup can't name, so it goes too, as the clear took
    /// it. Copies of one `id` stay: duplicate cleanup folds them as ever.
    /// A deleted record first lets go of the records the backup holds that
    /// it would take with it (`releaseKeptRecords`). Like `deleteAll`,
    /// nothing is saved here.
    func deleteSharedRecordsTheBackupLacks(
        _ idsInBackup: [String: Set<UUID>],
        viewContext: NSManagedObjectContext
    ) throws {
        let store = BackupRestoreScope.privateStore(of: viewContext)
        for entity in BackupEntityTable.entities {
            guard let kept = idsInBackup[entity.name],
                  let entityName = BackupFetchHelper.entityName(for: entity.managedType(), in: viewContext)
            else { continue }
            let objectIDColumn = NSExpressionDescription()
            objectIDColumn.name = "objectID"
            objectIDColumn.expression = NSExpression.expressionForEvaluatedObject()
            objectIDColumn.expressionResultType = .objectIDAttributeType
            let request = NSFetchRequest<NSDictionary>(entityName: entityName)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["id", objectIDColumn]
            if let store { request.affectedStores = [store] }
            for row in try viewContext.fetch(request) {
                guard let objectID = row["objectID"] as? NSManagedObjectID else { continue }
                if let id = row["id"] as? UUID, kept.contains(id) { continue }
                let record = viewContext.object(with: objectID)
                releaseKeptRecords(from: record, idsInBackup)
                viewContext.delete(record)
            }
        }
    }

    /// Takes out of `record`'s cascade relationships each record the
    /// backup holds (by `idsInBackup`), so deleting `record` doesn't delete
    /// it too. Once the clear took both and the import inserted the backup's
    /// copy unlinked; updated in place, it still links the record the backup
    /// lacks (a staple's history rows: `Supply.transactions`).
    private func releaseKeptRecords(from record: NSManagedObject, _ idsInBackup: [String: Set<UUID>]) {
        for (name, relationship) in record.entity.relationshipsByName
        where relationship.deleteRule == .cascadeDeleteRule {
            guard let destination = relationship.destinationEntity?.name, let kept = idsInBackup[destination] else {
                continue
            }
            let isKept = { (other: NSManagedObject) in
                (other.value(forKey: "id") as? UUID).map(kept.contains) ?? false
            }
            if relationship.isToMany {
                let linked = record.mutableSetValue(forKey: name)
                for case let other as NSManagedObject in linked.allObjects where isKept(other) {
                    linked.remove(other)
                }
            } else if let other = record.value(forKey: name) as? NSManagedObject, isKept(other) {
                record.setValue(nil, forKey: name)
            }
        }
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
