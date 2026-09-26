import Foundation
import CoreData
import SwiftUI
import CryptoKit
import Compression
import OSLog

// MARK: - Data Collection & Export Pipeline

extension BackupService {

    private static let logger = Logger.backup

    /// Collects every backup-eligible Core Data entity into a `BackupPayload`
    /// in one main-actor pass over `entityCollectors`, reporting the same
    /// progress lines as always. The one-pass export (the streamed export's
    /// fallback) and callers that want the whole database as values use this;
    /// the streamed export runs the same collectors one entity type at a time.
    public func collectPayload(
        viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback = { _, _ in }
    ) -> BackupPayload {
        var payload = BackupPayload.collecting(preferences: buildPreferencesDTO())
        for collector in Self.entityCollectors {
            if let announcement = collector.announcement {
                progress(
                    BackupProgress.progress(for: .collecting, subProgress: announcement.fraction),
                    announcement.message
                )
            }
            collector.collect(self, viewContext, &payload)
        }
        return payload
    }

    // MARK: - Batched Fetch Utilities

    /// Modern fetch-and-transform pattern that converts entities to DTOs in batches.
    /// This reduces peak memory usage by not holding both models and DTOs simultaneously.
    func fetchAndTransformInBatches<T: NSManagedObject, DTO>(
        _ type: T.Type,
        using context: NSManagedObjectContext,
        batchSize: Int = 1000,
        transform: ([T]) -> [DTO]
    ) -> [DTO] {
        // Guard: ensure the entity is registered in the context's model before fetching.
        // Without this, T.fetchRequest() throws an unrecoverable ObjC NSException
        // when the persistent stores haven't fully loaded (e.g. during pre-migration backup).
        let typeName = String(describing: T.self)
        guard let coordinator = context.persistentStoreCoordinator else {
            Self.logger.warning(
                "Skipping fetch for \(typeName, privacy: .public) — no persistent store coordinator"
            )
            return []
        }

        // Resolve the entity NAME from THIS context's model rather than the
        // `T.entity()` class method (which also serves as the "entity exists" guard).
        // When more than one NSManagedObjectModel is loaded in the process (e.g. a
        // test host app's stack alongside an in-memory test stack), `T.entity().name`
        // can return nil — and a fetch keyed on the class name ("CDStudent") instead
        // of the entity name ("Student") raises an uncaught NSException. The
        // per-coordinator model lookup is unambiguous.
        guard let entityName = coordinator.managedObjectModel.entitiesByName.values
            .first(where: { $0.managedObjectClassName == NSStringFromClass(T.self) })?.name else {
            Self.logger.info(
                "Skipping fetch for \(typeName, privacy: .public) — no entity in model"
            )
            return []
        }

        var allDTOs: [DTO] = []
        var offset = 0

        while true {
            // Fetch, transform, and release in one autoreleasepool
            let dtos: [DTO]? = autoreleasepool {
                let descriptor = NSFetchRequest<T>(entityName: entityName)
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = batchSize

                let batch: [T]
                do {
                    batch = try context.fetch(descriptor)
                } catch {
                    let typeName = String(describing: T.self)
                    let desc = error.localizedDescription
                    Self.logger.warning(
                        "Batch fetch failed \(typeName, privacy: .public): \(desc, privacy: .public)"
                    )
                    return nil
                }

                guard !batch.isEmpty else {
                    return nil
                }

                // Transform to DTOs immediately while models are in scope
                let transformed = transform(batch)

                // Batch objects are released when autoreleasepool exits
                return transformed
            }

            guard let fetchedDTOs = dtos, !fetchedDTOs.isEmpty else { break }
            allDTOs.append(contentsOf: fetchedDTOs)

            if fetchedDTOs.count < batchSize { break }
            offset += batchSize
        }

        return allDTOs
    }
}
