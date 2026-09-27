// BackupService+EntityCollectors.swift
// The export's collection step, one backed-up entity type per row.
//
// `collectPayload` runs every row into one payload. The streamed export
// (`BackupWriter+Streaming`) runs them one at a time and encodes each type
// before collecting the next, so only one type's DTOs are alive at once.
// Both paths read this table, so they fetch the same rows through the same
// transformers in the same order. Rows are in archive order — the order of
// `BackupWriter.entitySerializations`, which `BackupStreamingExportTests` pins.

import CoreData
import Foundation

extension BackupService {

    /// A progress line reported just before one entity type is collected: a
    /// sub-progress within `BackupProgress.Phase.collecting` and its message.
    nonisolated struct CollectionAnnouncement: Sendable {
        let fraction: Double
        let message: String

        init(_ fraction: Double, _ message: String) {
            self.fraction = fraction
            self.message = message
        }
    }

    /// Collects one backed-up entity type: every row, fetched from the view
    /// context in batches (`fetchAndTransformInBatches`) and stored as DTOs in
    /// the matching `BackupPayload` field.
    nonisolated struct EntityCollector: Sendable {
        /// The archive entity name ("Student", "WorkParticipantEntity", …).
        let entityName: String
        let announcement: CollectionAnnouncement?
        let collect: @MainActor (BackupService, NSManagedObjectContext, inout BackupPayload) -> Void

        /// A row for one of the payload's always-present arrays.
        static func required<Object: NSManagedObject, DTO>(
            _ entityName: String,
            _ type: Object.Type,
            _ field: WritableKeyPath<BackupPayload, [DTO]> & Sendable,
            _ transform: @escaping @MainActor ([Object]) -> [DTO],
            announcing announcement: CollectionAnnouncement? = nil
        ) -> EntityCollector {
            EntityCollector(entityName: entityName, announcement: announcement) { service, context, payload in
                payload[keyPath: field] = service.fetchAndTransformInBatches(type, using: context, transform: transform)
            }
        }

        /// A row for one of the payload's later-format (optional) arrays. The
        /// collector always stores an array, empty or not, never `nil`.
        static func optional<Object: NSManagedObject, DTO>(
            _ entityName: String,
            _ type: Object.Type,
            _ field: WritableKeyPath<BackupPayload, [DTO]?> & Sendable,
            _ transform: @escaping @MainActor ([Object]) -> [DTO],
            announcing announcement: CollectionAnnouncement? = nil
        ) -> EntityCollector {
            EntityCollector(entityName: entityName, announcement: announcement) { service, context, payload in
                payload[keyPath: field] = service.fetchAndTransformInBatches(type, using: context, transform: transform)
            }
        }
    }

    /// Every backed-up entity type, in archive order: `BackupEntityTable`'s.
    static let entityCollectors: [EntityCollector] = BackupEntityTable.entities.map(\.collector)
}
