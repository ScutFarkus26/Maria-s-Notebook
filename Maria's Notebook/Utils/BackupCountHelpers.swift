import Foundation
import OSLog
import CoreData

private let logger = Logger.backup

/// Helper functions for counting and filtering entities during backup operations.
/// Reduces duplication in BackupService restore operations.
enum BackupCountHelpers {
    /// Counts entities that exist in the store vs. those that don't.
    /// - Parameters:
    ///   - items: Array of items to check
    ///   - type: The NSManagedObject type
    ///   - context: The NSManagedObjectContext to check against
    ///   - exists: Function to check if an item exists
    /// - Returns: Tuple of (insertCount, skipCount)
    static func countInsertAndSkip<T>(
        items: [T],
        type: NSManagedObject.Type,
        context: NSManagedObjectContext,
        exists: (T) -> Bool
    ) -> (insert: Int, skip: Int) {
        let insertCount = items.filter { !exists($0) }.count
        let skipCount = items.filter { exists($0) }.count
        return (insert: insertCount, skip: skipCount)
    }

    /// Creates a helper function for checking entity existence by ID.
    /// - Parameters:
    ///   - type: The NSManagedObject type
    ///   - context: The NSManagedObjectContext to check against
    ///   - fetchOne: Function to fetch a single entity by ID
    /// - Returns: A function that checks if an item with the given ID exists
    static func makeExistsChecker<T: NSManagedObject>(
        type: T.Type,
        context: NSManagedObjectContext,
        fetchOne: @escaping (T.Type, _ id: UUID, _ using: NSManagedObjectContext) throws -> T?
    ) -> (UUID) -> Bool {
        return { id in
            do {
                let result = try fetchOne(type, id, context)
                return result != nil
            } catch {
                logger.warning("Failed to check existence for \(type, privacy: .public): \(error, privacy: .public)")
                return false
            }
        }
    }
}
