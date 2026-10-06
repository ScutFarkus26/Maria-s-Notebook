import Foundation
import CoreData

/// Shared lookup helpers for the backup system's "does this record already
/// exist?" and "find the parent for this relationship" checks.
///
/// Both replace the previous one-fetch-request-per-record pattern (a classic
/// Core Data import anti-pattern: a 10k-row restore issued 10k+ fetch
/// requests). Each entity type is now fetched at most twice (once per cache),
/// and every subsequent lookup is a dictionary hit.
enum BackupFetchHelper {
    /// Resolves the model entity name for a managed-object class by matching
    /// the class name. This works for *every* backed-up type — including
    /// classes whose name differs from the entity name (e.g.
    /// `CDCommunityTopicEntity` -> "CommunityTopic").
    static func entityName(
        for type: NSManagedObject.Type,
        in context: NSManagedObjectContext
    ) -> String? {
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else { return nil }
        return model.entitiesByName.values.first(where: {
            $0.managedObjectClassName == NSStringFromClass(type)
        })?.name
    }
}

/// Two separate per-entity-type caches for restore, because the two questions
/// need data captured at different moments — and at different weights:
///
/// - `existing` (upsert target): "was this record in the store *before* this
///   restore began, and if so, which object is it?" Backed by an id → objectID
///   map from a dictionary fetch, so nothing is materialized until an importer
///   actually updates a matching row (then only that row is faulted in). The
///   map is built the first time a type is imported — i.e. before that type's
///   own rows are inserted — which is exactly right: replace-mode has already
///   cleared the store, and duplicates within a type were removed as the
///   restore's source handed the type over (`BackupRestoreSource`), so the
///   only thing that should count as "already exists" is a pre-restore row
///   (merge mode). Dictionary fetches don't see pending inserts, which
///   reinforces that pre-restore-only semantic.
///
/// - `related` (relationship target): "find the parent with this id, whether
///   it pre-existed OR was just inserted earlier in this same restore." This one
///   genuinely needs objects, so it keeps the full fetch. Its map is built the
///   first time a *child* type asks for a parent — which, because the importer
///   always imports parents before children, happens *after* the parent type is
///   fully inserted. The `context.fetch` includes pending inserts, so
///   same-restore parents are found.
///
/// Keeping the two caches separate is load-bearing: a single shared map would
/// be frozen by the early existence lookup and would then miss every
/// same-restore parent on a fresh device (replace mode), silently dropping all
/// intra-restore relationships.
///
/// Both read only the private store when the notebook has two
/// (`BackupRestoreScope`): a restore writes the guide's own notebook, never a
/// classroom someone else shared into the shared store. When synced copies
/// share an `id`, both return the copy duplicate cleanup keeps
/// (`DataCleanupService.precedesAsCanonical`), so the restore's values land on
/// the row that survives rather than on one that is about to be deleted.
final class BackupEntityIndex {
    private let context: NSManagedObjectContext
    /// The store the restore reads and writes, or nil for "every store" (a
    /// notebook with one store).
    private let store: NSPersistentStore?
    /// For the duplicate keeper's record names; nil without CloudKit.
    private let container: NSPersistentCloudKitContainer?
    /// Values the backup's format can't carry, kept on the records the
    /// restore updates (`BackupPredatedValues`).
    let predatedValues: BackupPredatedValues
    private var existingObjectIDs: [ObjectIdentifier: [UUID: NSManagedObjectID]] = [:]
    private var relationshipMaps: [ObjectIdentifier: [UUID: NSManagedObject]] = [:]

    /// - Parameters:
    ///   - formatVersion: the backup's format, for the attributes it predates.
    ///     The current format (the default) predates none.
    ///   - container: the notebook's container, when it has one, so duplicates
    ///     are ordered by record name exactly as duplicate cleanup orders them.
    init(
        context: NSManagedObjectContext,
        formatVersion: Int = BackupWriter.formatVersion,
        container: NSPersistentCloudKitContainer? = nil
    ) {
        self.context = context
        store = BackupRestoreScope.privateStore(of: context)
        self.container = container
        predatedValues = BackupPredatedValues(formatVersion: formatVersion)
    }

    /// Upsert-target lookup. See the type-level note: built early, so it
    /// reflects pre-restore state only. Returns the stored object (as a fault
    /// until the importer touches it) or nil when the ID is new — or when the
    /// record is about to be deleted (a replace restore's clear, which is
    /// saved together with the import).
    func existing<T: NSManagedObject>(_ type: T.Type, id: UUID) throws -> T? {
        let key = ObjectIdentifier(type)
        if existingObjectIDs[key] == nil {
            existingObjectIDs[key] = try buildObjectIDMap(type)
        }
        guard let objectID = existingObjectIDs[key]?[id],
              let object = try context.existingObject(with: objectID) as? T,
              !object.isDeleted
        else { return nil }
        predatedValues.remember(object)
        return object
    }

    /// Relationship-target lookup. See the type-level note: built lazily at
    /// child-import time, so it includes parents inserted in this restore.
    func related<T: NSManagedObject>(_ type: T.Type, id: UUID) throws -> T? {
        let key = ObjectIdentifier(type)
        if relationshipMaps[key] == nil {
            relationshipMaps[key] = try buildMap(type)
        }
        return relationshipMaps[key]?[id] as? T
    }

    /// Reads just the `id` column plus each row's objectID — one narrow query
    /// per type, no live objects (only same-id copies are faulted in, to pick
    /// the one cleanup keeps).
    private func buildObjectIDMap<T: NSManagedObject>(_ type: T.Type) throws -> [UUID: NSManagedObjectID] {
        guard let entityName = BackupFetchHelper.entityName(for: type, in: context) else {
            return [:]
        }
        let objectIDColumn = NSExpressionDescription()
        objectIDColumn.name = "objectID"
        objectIDColumn.expression = NSExpression.expressionForEvaluatedObject()
        objectIDColumn.expressionResultType = .objectIDAttributeType

        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id", objectIDColumn]
        if let store { request.affectedStores = [store] }
        let rows = try context.fetch(request)

        var map: [UUID: NSManagedObjectID] = [:]
        var copies: [UUID: [NSManagedObjectID]] = [:]
        map.reserveCapacity(rows.count)
        for row in rows {
            guard let id = row["id"] as? UUID, let objectID = row["objectID"] as? NSManagedObjectID else { continue }
            if let first = map[id] {
                copies[id, default: [first]].append(objectID)
            } else {
                map[id] = objectID
            }
        }
        for (id, objectIDs) in copies {
            let keeper = objectIDs.map { context.object(with: $0) }.min(by: precedes)
            map[id] = keeper?.objectID ?? map[id]
        }
        return map
    }

    private func buildMap<T: NSManagedObject>(_ type: T.Type) throws -> [UUID: NSManagedObject] {
        guard let entityName = BackupFetchHelper.entityName(for: type, in: context) else {
            return [:]
        }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        // Load attributes in one pass — keying by `id` would otherwise fire a
        // fault per object. Pending inserts are included by default
        // (includesPendingChanges), which is what `related` relies on. The
        // store is filtered here rather than with `affectedStores`, so a
        // pending insert not yet given a store is never left out.
        request.returnsObjectsAsFaults = false

        var map: [UUID: NSManagedObject] = [:]
        for object in try context.fetch(request) {
            guard let id = object.value(forKey: "id") as? UUID, isInScope(object) else { continue }
            if let current = map[id], precedes(current, object) { continue }
            map[id] = object
        }
        return map
    }

    /// True for a record in the restore's store, or not yet in any store.
    private func isInScope(_ object: NSManagedObject) -> Bool {
        guard let store, let home = object.objectID.persistentStore else { return true }
        return home === store
    }

    /// Duplicate cleanup's order (1C owns it): the first is the copy it keeps.
    private func precedes(_ lhs: NSManagedObject, _ rhs: NSManagedObject) -> Bool {
        DataCleanupService.precedesAsCanonical(lhs, rhs, container: container)
    }
}

/// Where a restore reads and writes: the guide's private store. A notebook's
/// shared store holds only classrooms other people shared with it, which a
/// restore of this notebook's backup must neither clear, update nor fill.
enum BackupRestoreScope {
    /// The private store when the coordinator holds more than one store; nil
    /// when it holds one (the unified local store, Sample Class, the tests'
    /// in-memory stack), where there is nothing to choose between.
    nonisolated static func privateStore(of context: NSManagedObjectContext) -> NSPersistentStore? {
        guard let stores = context.persistentStoreCoordinator?.persistentStores, stores.count > 1 else { return nil }
        return stores.first { $0.configurationName == CoreDataStack.privateConfiguration }
    }

    /// Limits `request` to the private store when there's a choice: what a
    /// backup holds is what a restore writes back. A shared store's rows (a
    /// classroom someone else shared with this notebook) used to be backed up
    /// too, and every restore and checkpoint rollback then brought them back as
    /// private copies beside the originals (2026-10-05 review).
    nonisolated static func limitToNotebook(
        _ request: NSFetchRequest<some NSFetchRequestResult>, in context: NSManagedObjectContext
    ) {
        guard let store = privateStore(of: context) else { return }
        request.affectedStores = [store]
    }

    /// Gives every record the restore inserted to the private store before
    /// the save. Core Data would put most there anyway (the private store is
    /// added first), but nothing then depends on store order.
    static func assignInsertsToPrivateStore(in context: NSManagedObjectContext) {
        guard let store = privateStore(of: context),
              let model = context.persistentStoreCoordinator?.managedObjectModel
        else { return }
        let entities = model.entities(forConfigurationName: CoreDataStack.privateConfiguration) ?? []
        let homes = Set(entities.compactMap(\.name))
        for object in context.insertedObjects where homes.contains(object.entity.name ?? "") {
            context.assign(object, to: store)
        }
    }

    /// The notebook's CloudKit container, when `context` is the app's own
    /// notebook: duplicate cleanup orders same-id copies by record name, and
    /// the restore must pick the same copy. Nil for any other context (tests,
    /// a stack the app didn't make), where cleanup's other tie-breaks apply.
    @MainActor
    static func container(for context: NSManagedObjectContext) -> NSPersistentCloudKitContainer? {
        guard let stack = AppBootstrapping._sharedCoreDataStack,
              stack.container.persistentStoreCoordinator === context.persistentStoreCoordinator
        else { return nil }
        return stack.container
    }

    /// Whether `context` writes to a notebook that syncs with iCloud: the
    /// app's own, opened with CloudKit. False for any other store (the tests',
    /// the database-error screen's fresh notebook) and for the app's own while
    /// iCloud sync is off or CloudKit failed to start.
    @MainActor
    static func syncsWithICloud(_ context: NSManagedObjectContext) -> Bool {
        guard container(for: context) != nil else { return false }
        return AppBootstrapping._sharedCoreDataStack?.isCloudKitActive == true
    }
}

/// ID-set existence cache for restore PREVIEW: one `id`-only dictionary fetch
/// per entity type the payload references, then pure set lookups. Preview
/// never mutates the context, so set staleness isn't a concern here.
final class EntityIDIndexCache {
    private let context: NSManagedObjectContext
    private var idSets: [ObjectIdentifier: Set<UUID>] = [:]

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func exists(_ type: NSManagedObject.Type, id: UUID) -> Bool {
        let key = ObjectIdentifier(type)
        if idSets[key] == nil {
            // Mirror the old per-record behavior on fetch error: treat as
            // not-existing (preview shows it as an insert).
            idSets[key] = (try? fetchAllIDs(type)) ?? []
        }
        return idSets[key]?.contains(id) ?? false
    }

    private func fetchAllIDs(_ type: NSManagedObject.Type) throws -> Set<UUID> {
        guard let entityName = BackupFetchHelper.entityName(for: type, in: context) else {
            return []
        }
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        let rows = try context.fetch(request)
        return Set(rows.compactMap { $0["id"] as? UUID })
    }
}
