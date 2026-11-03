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

    /// Every row of `T` as DTOs, read a page (`batchSize` rows) at a time so no
    /// more than one page of managed objects is alive at once — from an on-disk
    /// store. An in-memory store is read in one fetch: its rows are all in
    /// memory already, and it gets an unsorted fetch's offset and limit wrong
    /// (2026-09-27: of 1,205 notes, the second 1,000-row page held 1, so the
    /// backup had 1,001).
    ///
    /// Pages come from the store alone (`includesPendingChanges = false`): the
    /// type's saved rows are listed once, by object ID, and each page reads
    /// the next `batchSize` of those IDs (`SELF IN`), in the listed order.
    /// Until 2026-11 each page was read by offset instead, so a row a CloudKit
    /// import deleted between two pages shifted every later row back by one
    /// and the row at the page boundary was in neither page (bug hunt
    /// 2026-11-02 #16); a row deleted now is just missing from its page.
    /// Unsaved edits still reach the backup: a fetch hands back the context's
    /// own object, pending updates and all; a row the context has deleted is
    /// left out; rows it has inserted are added once, after the saved ones.
    /// Until 2026-09-26 the pages were read with the unsaved edits mixed in, so
    /// in a type past one page an unsaved insert was written twice and pushed a
    /// saved row off the first page, and an unsaved delete on the first page had
    /// another row written twice; and the loop stopped at the first page that
    /// produced fewer DTOs than `batchSize`, so one malformed row (which the
    /// transformers skip) on a full page left every later page out.
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
            Self.logger.info("Skipping fetch for \(typeName, privacy: .public) — no entity in model")
            return []
        }

        var allDTOs: [DTO]
        if Self.readsWhole(coordinator) {
            // One fetch, so nothing can shift between pages.
            let descriptor = NSFetchRequest<T>(entityName: entityName)
            BackupRestoreScope.limitToNotebook(descriptor, in: context)
            descriptor.includesPendingChanges = false
            let rows = fetchLoggingFailure(descriptor, typeName: typeName, in: context) ?? []
            allDTOs = autoreleasepool { transform(rows.filter { !$0.isDeleted }) }
        } else {
            allDTOs = transformInPagesByID(
                T.self, entityName: entityName, using: context, batchSize: batchSize, transform: transform
            )
        }

        // Unsaved inserts, in a stable order so two collections agree.
        let inserted = context.insertedObjects
            .filter { $0.entity.name == entityName && !$0.isDeleted }
            .compactMap { $0 as? T }
            .map { (key: $0.objectID.uriRepresentation().absoluteString, object: $0) }
            .sorted { $0.key < $1.key }
            .map(\.object)
        if !inserted.isEmpty {
            allDTOs.append(contentsOf: autoreleasepool { transform(inserted) })
        }

        return allDTOs
    }

    /// The saved rows of `entityName` as DTOs, a page of `batchSize` object
    /// IDs at a time from one listing of the IDs (`fetchAndTransformInBatches`).
    private func transformInPagesByID<T: NSManagedObject, DTO>(
        _ type: T.Type,
        entityName: String,
        using context: NSManagedObjectContext,
        batchSize: Int,
        transform: ([T]) -> [DTO]
    ) -> [DTO] {
        let typeName = String(describing: T.self)
        let listing = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
        BackupRestoreScope.limitToNotebook(listing, in: context)
        listing.resultType = .managedObjectIDResultType
        listing.includesPendingChanges = false
        let ids = fetchLoggingFailure(listing, typeName: typeName, in: context) ?? []

        var dtos: [DTO] = []
        var start = 0
        while start < ids.count {
            let pageIDs = Array(ids[start..<min(start + batchSize, ids.count)])
            start += pageIDs.count
            // Fetch, transform, and release in one autoreleasepool
            let page: [DTO]? = autoreleasepool {
                let descriptor = NSFetchRequest<T>(entityName: entityName)
                descriptor.predicate = NSPredicate(format: "SELF IN %@", pageIDs)
                descriptor.includesPendingChanges = false
                guard let rows = fetchLoggingFailure(descriptor, typeName: typeName, in: context) else {
                    return nil
                }
                // In the listed order, as the pages by offset were.
                let place = Dictionary(uniqueKeysWithValues: pageIDs.enumerated().map { ($1, $0) })
                let batch = rows.filter { !$0.isDeleted }
                    .sorted { (place[$0.objectID] ?? 0) < (place[$1.objectID] ?? 0) }
                // Transform to DTOs immediately while models are in scope.
                // Batch objects are released when autoreleasepool exits.
                return transform(batch)
            }
            guard let page else { break }
            dtos.append(contentsOf: page)
        }
        return dtos
    }

    /// `request`'s results, or nil (logged) when the fetch failed.
    private func fetchLoggingFailure<R: NSFetchRequestResult>(
        _ request: NSFetchRequest<R>, typeName: String, in context: NSManagedObjectContext
    ) -> [R]? {
        do {
            return try context.fetch(request)
        } catch {
            let desc = error.localizedDescription
            Self.logger.warning("Batch fetch failed \(typeName, privacy: .public): \(desc, privacy: .public)")
            return nil
        }
    }

    /// Whether every store behind `coordinator` is in memory, so the export
    /// reads each type in one fetch instead of pages.
    private static func readsWhole(_ coordinator: NSPersistentStoreCoordinator) -> Bool {
        let stores = coordinator.persistentStores
        return !stores.isEmpty && stores.allSatisfy { $0.type == NSInMemoryStoreType }
    }
}
