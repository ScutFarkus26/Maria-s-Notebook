import Foundation
import CoreData

/// Helper for fetching entities by ID in the backup system.
/// Consolidates the merge-mode "does this record already exist?" lookup.
@MainActor
struct BackupFetchHelper {
    /// Fetches the single managed object of `type` whose `id` matches, or nil
    /// if none exists.
    ///
    /// The entity name is resolved from the loaded model by matching the
    /// managed-object class, so this works for *every* backed-up type —
    /// including classes whose name differs from the entity name (e.g.
    /// `CDCommunityTopicEntity` -> "CommunityTopic"). This mirrors the lookup
    /// `BackupService+DataCollection` uses to collect each type.
    ///
    /// This was previously a hand-maintained `if type == …` chain covering only
    /// ~16 of the ~55 backed-up types and returning nil for the rest. Because
    /// the merge-restore duplicate guard (`existingCheck`) relies on this, every
    /// unhandled type was treated as "not present" and re-inserted as a
    /// duplicate on a merge restore.
    static func fetchOne<T: NSManagedObject>(
        _ type: T.Type,
        id: UUID,
        using context: NSManagedObjectContext
    ) throws -> T? {
        guard let model = context.persistentStoreCoordinator?.managedObjectModel,
              let entityName = model.entitiesByName.values.first(where: {
                  $0.managedObjectClassName == NSStringFromClass(T.self)
              })?.name else {
            return nil
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first as? T
    }
}
