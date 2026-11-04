import Foundation
import CoreData
import OSLog

/// Entity names by managed-object class name, for the model they were read
/// from. Every request used to look through all the model's entities for its
/// class (bug hunt 2026-11-03 #15); a different model starts the map afresh.
/// Behind `entityNamesLock`, as `CoreDataStack.activeModel` is.
nonisolated(unsafe) private var entityNamesModel: NSManagedObjectModel?
nonisolated(unsafe) private var entityNamesByClass: [String: String] = [:]
nonisolated private let entityNamesLock = NSLock()

/// The entity `className` maps to in `model`, from the map once it's built:
/// the first entity for that class, as the search it replaces found it, and
/// nil when there's none or its name is empty.
nonisolated private func entityName(forClassName className: String, in model: NSManagedObjectModel) -> String? {
    entityNamesLock.lock()
    defer { entityNamesLock.unlock() }
    if entityNamesModel !== model {
        var names: [String: String] = [:]
        for entity in model.entities where names[entity.managedObjectClassName] == nil {
            names[entity.managedObjectClassName] = entity.name ?? ""
        }
        entityNamesModel = model
        entityNamesByClass = names
    }
    guard let name = entityNamesByClass[className], !name.isEmpty else { return nil }
    return name
}

/// Creates a typed NSFetchRequest using the Core Data entity name resolved
/// from the managed object model's representedClassName mapping.
///
/// - Important: The entity's `representedClassName` in the `.xcdatamodel` must
///   match the `@objc(...)` name on the Swift class, or `entity()` will fail.
nonisolated func CDFetchRequest<T: NSManagedObject>(_ type: T.Type = T.self) -> NSFetchRequest<T> {
    // Prefer model-based lookup (safe with multi-store configurations where
    // NSManagedObject.entity() can return an ambiguous/nil-named description).
    if let model = CoreDataStack.activeModel {
        if let name = entityName(forClassName: NSStringFromClass(type), in: model) {
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

nonisolated extension NSManagedObjectContext {
    private static let logger = Logger.database

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

    /// Faults in the object for `objectID` as `T` — nil when the row is gone or the ID is
    /// from another store; errors are not logged because callers treat absence as normal.
    func existing<T: NSManagedObject>(_ type: T.Type, _ objectID: NSManagedObjectID) -> T? {
        (try? existingObject(with: objectID)) as? T
    }

    /// Faults in the object for `objectID` — nil when the row is gone or the ID is from
    /// another store; errors are not logged because callers treat absence as normal.
    func existing(_ objectID: NSManagedObjectID) -> NSManagedObject? {
        try? existingObject(with: objectID)
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
