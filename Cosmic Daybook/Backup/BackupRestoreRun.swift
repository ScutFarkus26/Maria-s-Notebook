// BackupRestoreRun.swift
// One restore in progress: where each entity type's rows come from, where they
// go, and what a later step needs from an earlier one.

import CoreData
import Foundation
import OSLog

/// The backup a restore reads: the facts its summary reports, its settings,
/// and its rows — one entity type at a time, each type deduplicated as it is
/// read (the first row of each `id` kept, within the type: the deduplication
/// never worked across types).
protocol BackupRestoreSource: AnyObject {
    /// The file-level facts the restore's summary reports.
    var envelope: BackupEnvelope { get }
    /// The settings the backup carries.
    var preferences: PreferencesDTO { get }
    /// The types whose entry is in the backup but couldn't be read (every row
    /// of it skipped, with a warning). The backup says nothing about them, so a
    /// Replace leaves them as they are, and won't run without a required one.
    /// A type with no entry at all is one the notebook had none of: the
    /// archive carries only non-empty entries.
    var skippedEntityNames: Set<String> { get }

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
    let skippedEntityNames: Set<String>
    private var payload: BackupPayload

    /// - Parameter skipped: the archive entries that didn't decode
    ///   (`BackupImporter.DecodedArchive.skippedEntityNames`); none for a
    ///   payload built in memory.
    init(_ payload: BackupPayload, envelope: BackupEnvelope, skipped: Set<String> = []) {
        self.payload = payload
        self.envelope = envelope
        skippedEntityNames = skipped
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
    let mode: BackupService.RestoreMode
    /// One fetch per entity type, built lazily, so a type sees the parents
    /// imported before it in this same restore.
    let index: BackupEntityIndex
    private let source: any BackupRestoreSource

    /// For each classroom-share type a Replace updates in place, the ids of
    /// the backup's rows: what stays once the import is done
    /// (`BackupService.deleteSharedRecordsTheBackupLacks`).
    private(set) var sharedIDsInBackup: [String: Set<UUID>] = [:]

    /// The notes a Merge left as they are here, changed since the backup
    /// (`keepingNewer`): the backup's links to children for them are left
    /// too, or a note would show under a child it no longer names.
    private(set) var keptNoteIDs = Set<UUID>()

    /// The links of every restored note that has any, rewired once every type
    /// they point at is in (`BackupEntityImporter.relinkNoteRelationships`).
    var noteLinks: [BackupNoteLinks] = []
    /// Every restored note, whose student links are made to match its scope
    /// once the links themselves are in (`matchStudentLinksToScope`).
    var restoredNoteIDs: [UUID] = []
    /// Every restored student link: the backup's, which the restore keeps.
    var restoredLinkIDs = Set<UUID>()
    /// The albums the backup's bookmarks, page notes, highlights, ink and
    /// reading positions belong to, for the reattach warning.
    var albumIDs = Set<String>()
    /// Notes the backup links to a reminder this device doesn't have, for the
    /// summary: reminders aren't restored, so those links stay off.
    var notesMissingTheirReminder = 0

    init(source: any BackupRestoreSource, context: NSManagedObjectContext, mode: BackupService.RestoreMode) {
        self.source = source
        self.context = context
        self.mode = mode
        index = BackupEntityIndex(
            context: context,
            formatVersion: source.envelope.formatVersion,
            container: BackupRestoreScope.container(for: context)
        )
    }

    enum RunError: LocalizedError {
        case notBackedUp(String)

        var errorDescription: String? {
            switch self {
            case .notBackedUp:
                // A programming slip, not the guide's; the field is in the log.
                "The restore stopped partway. Try again."
            }
        }
    }

    /// The rows of the type stored in `field`, deduplicated, less those the
    /// restore leaves to the newer record already here (`keepingNewer`).
    func rows<DTO: BackupRowDTO>(_ field: WritableKeyPath<BackupPayload, [DTO]>) throws -> [DTO] {
        let entity = try importing(field)
        return try keepingNewer(source.rows(of: entity)[keyPath: field], of: entity)
    }

    /// The rows of the later-format type stored in `field`, deduplicated, less
    /// those the restore leaves to the newer record already here; nil when the
    /// backup has no entry for it (or none that decodes).
    func rows<DTO: BackupRowDTO>(_ field: WritableKeyPath<BackupPayload, [DTO]?>) throws -> [DTO]? {
        let entity = try importing(field)
        guard let rows = try source.rows(of: entity)[keyPath: field] else {
            noteSharedIDs([DTO](), of: entity)
            return nil
        }
        return try keepingNewer(rows, of: entity)
    }

    /// `rows` less each one whose record is already here and changed since
    /// (`BackupMergeRule.keepsStored`): a Merge adds what's missing and never
    /// rewinds a record changed since the backup (bug hunt 2026-11-02, #1),
    /// nor reopens a to-do done since. A row or record with no change date
    /// (a type without one, an older backup's row) is taken, as a Merge
    /// always took every row. A Replace takes every row, but for the types
    /// it updates as a Merge does (the names people set,
    /// `BackupEntityRegistry.mergedOnReplaceEntityNames`), where a name here
    /// with a date also stands against a backup row with none, as it has
    /// since 2026-10-29.
    private func keepingNewer<DTO: BackupRowDTO>(_ rows: [DTO], of entity: BackupEntity) throws -> [DTO] {
        noteSharedIDs(rows, of: entity)
        let isName = BackupEntityRegistry.mergedOnReplaceEntityNames.contains(entity.name)
        guard mode == .merge || isName else { return rows }
        let type = entity.managedType()
        var taken: [DTO] = []
        taken.reserveCapacity(rows.count)
        for row in rows {
            if let stored = try index.storedStamp(type, id: row.id),
               BackupMergeRule.keepsStored(
                   stored, rowChangedAt: row.rowModifiedAt, rowCompletedAt: row.rowCompletedAt,
                   keepsDatedOverDateless: isName
               ) {
                if entity.name == "Note" { keptNoteIDs.insert(row.id) }
                continue
            }
            taken.append(row)
        }
        return taken
    }

    /// Keeps the ids of a classroom-share type's rows for a Replace, which
    /// updates those records in place and then deletes only the ones the
    /// backup lacks (bug hunt 2026-11-02, #2). Not for a type the backup is
    /// too old to hold, nor one whose entry it couldn't read: it says nothing
    /// about those, and they stay as they are.
    private func noteSharedIDs<DTO: BackupRowDTO>(_ rows: [DTO], of entity: BackupEntity) {
        guard mode == .replace,
              BackupEntityRegistry.updatedInPlaceOnReplaceEntityNames.contains(entity.name),
              entity.isCarried(by: source.envelope.formatVersion),
              !source.skippedEntityNames.contains(entity.name)
        else { return }
        sharedIDsInBackup[entity.name] = Set(rows.map(\.id))
    }

    /// The type stored in `field`, as its import begins ("import <Entity>" for
    /// the pipeline probe, where a test can make the restore fail).
    private func importing(_ field: AnyKeyPath) throws -> BackupEntity {
        guard let entity = BackupEntityTable.entity(for: field) else {
            let name = String(describing: field)
            Logger.backup.fault("Restore asked for \(name, privacy: .public), which no backed-up type holds")
            throw RunError.notBackedUp("\(field)")
        }
        try BackupPipelineProbe.reachOrFail("import \(entity.name)")
        return entity
    }
}
