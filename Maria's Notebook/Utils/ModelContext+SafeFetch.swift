import Foundation
import SwiftData

extension ModelContext {
    /// Safely fetches entities, returning an empty array on error instead of throwing.
    /// - Parameter descriptor: The FetchDescriptor to use for the fetch
    /// - Returns: An array of fetched entities, or an empty array if the fetch fails
    func safeFetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? fetch(descriptor)) ?? []
    }
    
    /// Safely fetches a single entity, returning nil on error or if not found.
    /// - Parameter descriptor: The FetchDescriptor to use for the fetch
    /// - Returns: The fetched entity, or nil if the fetch fails or no entity is found
    func safeFetchFirst<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> T? {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        return safeFetch(descriptor).first
    }

    /// Fetches entities with automatic deduplication, throwing on error.
    /// CloudKit sync can create duplicate records with the same ID during merge conflicts.
    /// - Parameter descriptor: The FetchDescriptor to use for the fetch
    /// - Returns: A deduplicated array of fetched entities
    /// - Throws: Any error from the underlying fetch operation
    func fetchUnique<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        try fetch(descriptor).uniqueByID
    }
}

