// BackupRestoreRun.swift
// One restore in progress: where each entity type's rows come from, where they
// go, and what a later step needs from an earlier one.

import CoreData
import Foundation

/// The backup a restore reads: the facts its summary reports, its settings,
/// and its rows — one entity type at a time, each type deduplicated as it is
/// read (the first row of each `id` kept, within the type: the deduplication
/// never worked across types).
protocol BackupRestoreSource: AnyObject {
    /// The file-level facts the restore's summary reports.
    var envelope: BackupEnvelope { get }
    /// The settings the backup carries.
    var preferences: PreferencesDTO { get }

    /// A payload whose `entity` field holds that type's rows, deduplicated.
    /// The restore reads nothing else from it.
    func rows(of entity: BackupEntity) throws -> BackupPayload
}

/// A decoded payload as a restore's source. Each type is handed over once,
/// moved out of the payload and deduplicated in place (`BackupEntity.take`),
/// so the payload shrinks as the restore goes and never exists twice; a type
/// is freed as soon as its importer is done with it. When the source holds the
/// only copy — `BackupImporter.restore` makes sure of it — that is what bounds
/// the restore's memory. Tests that build a payload by hand restore through it
/// too (`BackupService.importPayload`), keeping their own copy.
final class BackupPayloadSource: BackupRestoreSource {
    let envelope: BackupEnvelope
    let preferences: PreferencesDTO
    private var payload: BackupPayload

    init(_ payload: BackupPayload, envelope: BackupEnvelope) {
        self.payload = payload
        self.envelope = envelope
        preferences = payload.preferences
    }

    func rows(of entity: BackupEntity) -> BackupPayload {
        var rows = BackupPayload.collecting(preferences: PreferencesDTO(values: [:]))
        entity.take(&payload, &rows)
        return rows
    }
}

/// One restore in progress. `BackupService.importRows` walks the restore
/// order through the `import…` methods (`+CoreTypes`, `+PlanningTypes`,
/// `+LaterTypes`); each reads its types through `rows(_:)` as it reaches them,
/// so a type's rows are alive only while it is imported.
///
/// Main-actor state, used within one main-actor turn: the view context's
/// queue, and nothing may suspend between a restore's clear and its save.
final class BackupRestoreRun {
    let context: NSManagedObjectContext
    /// One fetch per entity type, built lazily, so a type sees the parents
    /// imported before it in this same restore.
    let index: BackupEntityIndex
    private let source: any BackupRestoreSource

    /// The links of every restored note that has any, rewired once every type
    /// they point at is in (`BackupEntityImporter.relinkNoteRelationships`).
    var noteLinks: [BackupNoteLinks] = []
    /// The albums the backup's bookmarks, page notes, highlights, ink and
    /// reading positions belong to, for the reattach warning.
    var albumIDs = Set<String>()

    init(source: any BackupRestoreSource, context: NSManagedObjectContext) {
        self.source = source
        self.context = context
        index = BackupEntityIndex(context: context)
    }

    enum RunError: LocalizedError {
        case notBackedUp(String)

        var errorDescription: String? {
            switch self {
            case .notBackedUp(let field):
                "The restore asked for \(field), which no backed-up type holds."
            }
        }
    }

    /// The rows of the type stored in `field`, deduplicated.
    func rows<DTO>(_ field: WritableKeyPath<BackupPayload, [DTO]>) throws -> [DTO] {
        try source.rows(of: importing(field))[keyPath: field]
    }

    /// The rows of the later-format type stored in `field`, deduplicated; nil
    /// when the backup has no entry for it (or none that decodes).
    func rows<DTO>(_ field: WritableKeyPath<BackupPayload, [DTO]?>) throws -> [DTO]? {
        try source.rows(of: importing(field))[keyPath: field]
    }

    /// The type stored in `field`, as its import begins ("import <Entity>" for
    /// the pipeline probe, where a test can make the restore fail).
    private func importing(_ field: AnyKeyPath) throws -> BackupEntity {
        guard let entity = BackupEntityTable.entity(for: field) else {
            throw RunError.notBackedUp("\(field)")
        }
        try BackupPipelineProbe.reachOrFail("import \(entity.name)")
        return entity
    }
}
