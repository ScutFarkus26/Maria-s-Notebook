import Foundation
import CoreData
import OSLog

/// Creates a typed NSFetchRequest using the @objc class name as the entity name.
/// All CD entities use @objc(EntityName) which maps to the Core Data entity name.
func CDFetchRequest<T: NSManagedObject>(_ type: T.Type = T.self) -> NSFetchRequest<T> {
    NSFetchRequest<T>(entityName: NSStringFromClass(type))
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
