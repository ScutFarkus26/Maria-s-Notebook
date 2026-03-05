import Foundation
import OSLog
import SwiftData

private let logger = Logger.backup

/// Helper functions for counting and filtering entities during backup operations.
/// Reduces duplication in BackupService restore operations.
enum BackupCountHelpers {
    /// Counts entities that exist in the store vs. those that don't.
    /// - Parameters:
    ///   - items: Array of items to check
    ///   - type: The PersistentModel type
    ///   - modelContext: The ModelContext to check against
    ///   - exists: Function to check if an item exists
    /// - Returns: Tuple of (insertCount, skipCount)
    static func countInsertAndSkip<T>(
        items: [T],
        type: any PersistentModel.Type,
        modelContext: ModelContext,
        exists: (T) -> Bool
    ) -> (insert: Int, skip: Int) {
        let insertCount = items.filter { !exists($0) }.count
        let skipCount = items.filter { exists($0) }.count
        return (insert: insertCount, skip: skipCount)
    }
    
    /// Creates a helper function for checking entity existence by ID.
    /// - Parameters:
    ///   - type: The PersistentModel type
    ///   - modelContext: The ModelContext to check against
    ///   - fetchOne: Function to fetch a single entity by ID
    /// - Returns: A function that checks if an item with the given ID exists
    static func makeExistsChecker<T: PersistentModel>(
        type: T.Type,
        modelContext: ModelContext,
        fetchOne: @escaping (T.Type, _ id: UUID, _ using: ModelContext) throws -> T?
    ) -> (UUID) -> Bool {
        return { id in
            do {
                let result = try fetchOne(type, id, modelContext)
                return result != nil
            } catch {
                logger.warning("Failed to check existence for \(type, privacy: .public): \(error, privacy: .public)")
                return false
            }
        }
    }
}
