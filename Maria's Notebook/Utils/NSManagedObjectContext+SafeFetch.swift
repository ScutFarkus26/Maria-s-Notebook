import Foundation
import CoreData
import OSLog

/// Creates a typed NSFetchRequest using the Core Data entity name resolved
/// from the managed object model's representedClassName mapping.
///
/// - Important: The entity's `representedClassName` in the `.xcdatamodel` must
///   match the `@objc(...)` name on the Swift class, or `entity()` will fail.
func CDFetchRequest<T: NSManagedObject>(_ type: T.Type = T.self) -> NSFetchRequest<T> {
    // Prefer model-based lookup (safe with multi-store configurations where
    // NSManagedObject.entity() can return an ambiguous/nil-named description).
    if let model = CoreDataStack.activeModel {
        let className = NSStringFromClass(type)
        if let entity = model.entities.first(where: { $0.managedObjectClassName == className }),
           let name = entity.name, !name.isEmpty {
            return NSFetchRequest<T>(entityName: name)
        }
    }

    // Fallback to static entity() lookup (works in single-store mode)
    let entity = type.entity()
    guard let name = entity.name, !name.isEmpty else {
        fatalError(
            "CDFetchRequest: Could not resolve entity name for \(T.self). "
            + "Check that representedClassName in the .xcdatamodel matches "
            + "the @objc(...) annotation on the NSManagedObject subclass."
        )
    }
    return NSFetchRequest<T>(entityName: name)
}

extension NSManagedObjectContext {
    private static let logger = Logger.app(category: "database")

    /// Safely fetches entities, returning an empty array on error instead of throwing.
    func safeFetch<T: NSManagedObject>(_ request: NSFetchRequest<T>) -> [T] {
        do {
            return try fetch(request)
        } catch {
            Self.logger.error("Failed to fetch \(String(describing: T.self)): \(error.localizedDescription)")
            return []
        }
    }

    /// Safely fetches a single entity, returning nil on error or if not found.
    func safeFetchFirst<T: NSManagedObject>(_ request: NSFetchRequest<T>) -> T? {
        request.fetchLimit = 1
        return safeFetch(request).first
    }

    /// Fetches the one object of `type` whose `id` attribute equals `id`, or nil
    /// when it is absent or the fetch fails (logged).
    ///
    /// Every entity in the model keys `id` as a UUID, so this is the single
    /// fetch-by-id path: `CDFetchRequest` resolves the entity, the predicate is
    /// `id == %@`, and the limit is 1.
    func object<T: NSManagedObject>(_ type: T.Type, id: UUID) -> T? {
        let request = CDFetchRequest(type)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return safeFetchFirst(request)
    }

    /// Safely saves the context, logging errors.
    /// - Returns: true if save succeeded or no changes to save
    @discardableResult
    func safeSave() -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            return true
        } catch {
            // A failed save means user data didn't persist — make it loud. `.fault`
            // survives release log capture (unlike `.error`), so silently-swallowed
            // saves are at least visible. UI-facing call sites should prefer
            // `SaveCoordinator`, which surfaces a "Couldn't Save" alert to the user.
            Self.logger.fault("Failed to save context: \(error.localizedDescription)")
            return false
        }
    }
}
