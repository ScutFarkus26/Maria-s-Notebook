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

}
