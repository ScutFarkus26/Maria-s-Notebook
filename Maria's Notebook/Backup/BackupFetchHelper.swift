import Foundation
import CoreData

/// Shared lookup helpers for the backup system's "does this record already
/// exist?" and "find the parent for this relationship" checks.
///
/// Both replace the previous one-fetch-request-per-record pattern (a classic
/// Core Data import anti-pattern: a 10k-row restore issued 10k+ fetch
/// requests). Each entity type is now fetched at most twice (once per cache),
/// and every subsequent lookup is a dictionary hit.
@MainActor
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
/// - `exists` (existence / dedup): "was this record in the store *before* this
///   restore began?" An id-only dictionary fetch, so it never materializes an
///   object: the answer is a `Bool` and no caller has ever needed the record
///   itself. The set is built the first time a type is imported — i.e. before
///   that type's own rows are inserted — which is exactly right: replace-mode
///   has already cleared the store, and within-payload duplicates were removed
///   by `deduplicatePayload`, so the only thing that should count as "already
///   exists" is a pre-restore row (merge mode). Dictionary fetches don't see
///   pending inserts, which reinforces that pre-restore-only semantic.
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
/// be frozen by the early existence check and would then miss every
/// same-restore parent on a fresh device (replace mode), silently dropping all
/// intra-restore relationships.
@MainActor
final class BackupEntityIndex {
    private let context: NSManagedObjectContext
    private var existenceIDs: [ObjectIdentifier: Set<UUID>] = [:]
    private var relationshipMaps: [ObjectIdentifier: [UUID: NSManagedObject]] = [:]

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Existence / dedup check. See the type-level note: built early, so it
    /// reflects pre-restore state only.
    func exists<T: NSManagedObject>(_ type: T.Type, id: UUID) throws -> Bool {
        let key = ObjectIdentifier(type)
        if existenceIDs[key] == nil {
            existenceIDs[key] = try buildIDSet(type)
        }
        return existenceIDs[key]?.contains(id) ?? false
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

    /// Reads just the `id` column — same pattern as `EntityIDIndexCache` below.
    /// One narrow query per type instead of a full table of live objects.
    private func buildIDSet<T: NSManagedObject>(_ type: T.Type) throws -> Set<UUID> {
        guard let entityName = BackupFetchHelper.entityName(for: type, in: context) else {
            return []
        }
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        let rows = try context.fetch(request)
        return Set(rows.compactMap { $0["id"] as? UUID })
    }

    private func buildMap<T: NSManagedObject>(_ type: T.Type) throws -> [UUID: NSManagedObject] {
        guard let entityName = BackupFetchHelper.entityName(for: type, in: context) else {
            return [:]
        }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        // Load attributes in one pass — keying by `id` would otherwise fire a
        // fault per object. Pending inserts are included by default
        // (includesPendingChanges), which is what `related` relies on.
        request.returnsObjectsAsFaults = false

        var map: [UUID: NSManagedObject] = [:]
        for object in try context.fetch(request) {
            if let id = object.value(forKey: "id") as? UUID {
                map[id] = object
            }
        }
        return map
    }
}

/// ID-set existence cache for restore PREVIEW: one `id`-only dictionary fetch
/// per entity type the payload references, then pure set lookups. Preview
/// never mutates the context, so set staleness isn't a concern here.
@MainActor
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
