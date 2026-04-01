import Foundation
import CoreData
import OSLog

/// Creates a typed NSFetchRequest using the Core Data entity name resolved
/// from the managed object model's representedClassName mapping.
///
/// - Important: The entity's `representedClassName` in the `.xcdatamodel` must
///   match the `@objc(...)` name on the Swift class, or `entity()` will fail.
func CDFetchRequest<T: NSManagedObject>(_ type: T.Type = T.self) -> NSFetchRequest<T> {
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

    /// Safely saves the context, logging errors.
    /// - Returns: true if save succeeded or no changes to save
    @discardableResult
    func safeSave() -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            return true
        } catch {
            Self.logger.error("Failed to save context: \(error.localizedDescription)")
            return false
        }
    }
}
