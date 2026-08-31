import CoreData
import CryptoKit
import Foundation
import OSLog

// MARK: - Schema Version Guard
//
// Core Data will happily lightweight-migrate a store *backwards*. Point an
// older build at a store written by a newer one and — with
// `NSMigratePersistentStoresAutomaticallyOption` and
// `NSInferMappingModelAutomaticallyOption` both set, as `makeStoreDescription`
// sets them — it infers a reverse mapping and drops every table the older
// model does not know about.
//
// That is not hypothetical. On 2026-08-25 an Aug-14 archive build opened the
// shared container's `private.sqlite` and logged:
//
//     Migration: CloudKit tables detected. Adding migration statements for
//     removed table: ZGUARDIAN … ZALBUMBOOKMARK
//
// while two newer instances had the same file open. Their next store access
// failed with `NSCocoaErrorDomain 256` / `NSSQLiteErrorDomain 1`, the CloudKit
// mirroring delegate died, and one of them aborted inside
// `container.share(_:to:)` — see `SharedStoreZoneRepair.shareOffMain`.
//
// Note the model is versioned by *content*, not by name: both builds shipped a
// model literally called "MariasNotebook 2", because the single
// `.xcdatamodel` is edited in place. Names cannot be trusted, so this guard
// keys off an explicit monotonic stamp instead.

extension CoreDataStack {

    private static var schemaLogger: Logger { Logger.app(category: "CoreDataSchemaVersion") }

    /// Monotonic stamp for the compiled Core Data model.
    ///
    /// **Bump this in the same commit as any change to
    /// `MariasNotebook.xcdatamodeld`.** `CoreDataSchemaVersionTests` fails when
    /// the model's entity hashes change without a bump, so it cannot silently
    /// drift the way the model's *name* has.
    ///
    /// Written into every on-disk store under ``schemaVersionMetadataKey``. A
    /// build whose value is lower than the stamp it finds refuses to open that
    /// store rather than migrating it down — see
    /// ``verifyStoreIsNotFromNewerBuild(storeURL:)``.
    ///
    /// Version history:
    /// - `1` — first version to carry a stamp (Albums entities + `Guardian`).
    /// - `2` — `AttendanceRecord.recordedBy`/`modifiedAt` (assistant attribution)
    ///   and `Note.attendanceRecordID` (string-FK twin of the `attendanceRecord`
    ///   relationship, backfilled by `AttendanceNoteLinkBackfill` ahead of the
    ///   relationship's removal when attendance moves to the shared store).
    /// - `3` — `AttendanceRecord` moves to the shared store so an assistant can
    ///   write it, and the `AttendanceRecord.notes` ↔ `Note.attendanceRecord`
    ///   relationship is deleted (it would cross store configurations).
    ///   `Note.attendanceRecordID` is now the only link.
    nonisolated static let currentSchemaVersion = 3

    /// Store-metadata key holding the writing build's ``currentSchemaVersion``.
    nonisolated static let schemaVersionMetadataKey = "MNSchemaVersion"

    // MARK: - Model Digest

    /// Stable digest of a model's entity version hashes.
    ///
    /// `entityVersionHashesByName` is exactly what Core Data compares when it
    /// decides whether a store needs migrating, so any schema edit that would
    /// trigger a migration also changes this digest — and any edit that would
    /// not (renaming a fetch request, moving an entity in the editor) leaves it
    /// alone. That makes it the right tripwire for "the model changed but
    /// nobody bumped ``currentSchemaVersion``".
    nonisolated static func modelSchemaDigest(_ model: NSManagedObjectModel) -> String {
        let joined = model.entityVersionHashesByName
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.base64EncodedString())" }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Pre-Load Preparation

    /// Prepares every on-disk SQLite store for `loadPersistentStores`.
    ///
    /// Order matters. ``cleanOrphanEntityMetadata(storeURL:model:)`` exists to
    /// help a *forward* migration succeed by clearing metadata for entities the
    /// model has dropped. Run against a store from a newer build it would do
    /// the opposite favour — smoothing the path for the destructive backwards
    /// migration this guard exists to prevent. So the guard runs first, and the
    /// stamp goes on last.
    /// - Returns: store URL → rollback-copy URL, for every store this pass was
    ///   about to migrate. The caller restores these if the load still fails,
    ///   so a failed recovery attempt leaves the user exactly where they began.
    @discardableResult
    static func prepareStoresForLoad(
        container: NSPersistentContainer,
        model: NSManagedObjectModel
    ) throws -> [URL: URL] {
        var backups: [URL: URL] = [:]

        for description in container.persistentStoreDescriptions {
            guard let url = description.url, description.type == NSSQLiteStoreType else { continue }
            try verifyStoreIsNotFromNewerBuild(storeURL: url)

            // Migration is in-place and irreversible, and both cleanups below
            // edit the file. Copy it first, and only attempt the newer repair
            // when that copy exists.
            let migrating = storeNeedsMigration(
                storeURL: url,
                configuration: description.configuration,
                model: model
            )
            let backup = migrating ? backUpStoreBeforeMigration(storeURL: url) : nil
            if let backup { backups[url] = backup }

            // A store whose metadata claims compatibility can still be missing
            // columns (metadata rewritten by a half-finished migration). Core
            // Data won't migrate it — the hashes say there is nothing to do —
            // so catch the lie here. Migrating stores skip this: their
            // migration rebuilds the schema anyway.
            if !migrating {
                let findings = incoherentSchemaFindings(
                    storeURL: url,
                    configuration: description.configuration,
                    model: model
                )
                if !findings.isEmpty {
                    if description.configuration == sharedConfiguration {
                        // The shared store mirrors the CloudKit shared
                        // database; a rebuilt store re-imports from the server.
                        quarantineIncoherentStore(storeURL: url, findings: findings)
                    } else {
                        // Never silently rebuild the store that holds the
                        // user's primary data — surface it instead.
                        throw CoreDataStackError.storeSchemaIncoherent(
                            storeName: url.lastPathComponent,
                            detail: findings.sorted().joined(separator: ", ")
                        )
                    }
                }
            }

            cleanOrphanEntityMetadata(storeURL: url, model: model)
            if backup != nil {
                cleanDanglingCloudKitMetadata(storeURL: url)
                dedupeCloudKitMetadataForDuplicatedEntities(storeURL: url)
                logCloudKitMetadataShape(storeURL: url)
            }

            stampSchemaVersion(storeURL: url)
        }

        return backups
    }

    // MARK: - Guard

    /// Throws ``CoreDataStackError/storeFromNewerBuild(storeName:storeVersion:appVersion:)``
    /// when `storeURL` was last written by a build with a higher
    /// ``currentSchemaVersion`` than this one.
    ///
    /// Fails **open** on an unreadable or unstamped store: a store written
    /// before this guard shipped carries no stamp, and a metadata read that
    /// fails outright is a problem `loadPersistentStores` reports with a better
    /// message than anything this function could invent.
    static func verifyStoreIsNotFromNewerBuild(storeURL: URL) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let metadata: [String: Any]
        do {
            metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                type: .sqlite,
                at: storeURL
            )
        } catch {
            let msg = "Could not read schema stamp from \(storeURL.lastPathComponent): " +
                "\(error.localizedDescription)"
            schemaLogger.warning("\(msg, privacy: .public)")
            return
        }

        guard let stamped = metadata[schemaVersionMetadataKey] as? Int else { return }
        guard stamped > currentSchemaVersion else { return }

        let msg = "Refusing to open \(storeURL.lastPathComponent): schema stamp \(stamped) " +
            "is newer than this build's \(currentSchemaVersion). Opening it would " +
            "lightweight-migrate the store backwards and drop data."
        schemaLogger.fault("\(msg, privacy: .public)")
        throw CoreDataStackError.storeFromNewerBuild(
            storeName: storeURL.lastPathComponent,
            storeVersion: stamped,
            appVersion: currentSchemaVersion
        )
    }

    // MARK: - Stamping

    /// Records ``currentSchemaVersion`` in the store's on-disk metadata.
    ///
    /// Called before `loadPersistentStores`, while no coordinator of ours holds
    /// the file, so the write lands immediately rather than waiting for a save.
    /// Existing metadata keys are preserved — only ours is added.
    static func stampSchemaVersion(storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        do {
            var metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                type: .sqlite,
                at: storeURL
            )
            guard (metadata[schemaVersionMetadataKey] as? Int) != currentSchemaVersion else { return }
            metadata[schemaVersionMetadataKey] = currentSchemaVersion
            try NSPersistentStoreCoordinator.setMetadata(metadata, type: .sqlite, at: storeURL)
            let msg = "Stamped \(storeURL.lastPathComponent) with schema version \(currentSchemaVersion)"
            schemaLogger.info("\(msg, privacy: .public)")
        } catch {
            // Non-fatal: an unstamped store just isn't protected yet, and the
            // next launch tries again.
            let msg = "Could not stamp \(storeURL.lastPathComponent): \(error.localizedDescription)"
            schemaLogger.warning("\(msg, privacy: .public)")
        }
    }

    /// Re-applies the stamp after a successful load.
    ///
    /// ``stampSchemaVersion(storeURL:)`` alone is not enough for two launches:
    /// one that *creates* a store (no file existed pre-load, so there was
    /// nothing to stamp) and one that *migrates* a store (lightweight migration
    /// rewrites store metadata, dropping the pre-load stamp — precisely the
    /// launch after which the store is newest and most in need of the guard).
    static func restampSchemaVersion(in container: NSPersistentContainer) {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores where store.type == NSSQLiteStoreType {
            guard let url = store.url else { continue }
            var metadata = store.metadata ?? [:]
            guard (metadata[schemaVersionMetadataKey] as? Int) != currentSchemaVersion else { continue }
            metadata[schemaVersionMetadataKey] = currentSchemaVersion

            // Keep the coordinator's in-memory copy in step, so its next save
            // writes the stamp back out rather than over it…
            coordinator.setMetadata(metadata, for: store)

            // …and put it on disk now. `setMetadata(_:for:)` defers the write
            // to that next save, which on a launch that only reads may never
            // come — leaving the store unprotected until some later session
            // happens to stamp it pre-load.
            do {
                try NSPersistentStoreCoordinator.setMetadata(metadata, type: .sqlite, at: url)
            } catch {
                let msg = "Could not persist schema stamp for \(url.lastPathComponent): " +
                    "\(error.localizedDescription)"
                schemaLogger.warning("\(msg, privacy: .public)")
            }
        }
    }
}
