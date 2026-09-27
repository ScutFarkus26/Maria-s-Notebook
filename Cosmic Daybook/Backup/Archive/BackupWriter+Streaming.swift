// BackupWriter+Streaming.swift
// The export, one entity type at a time.
//
// The one-pass export collected the whole database as DTO structs before
// encoding any of it, so its peak held every record at once — at app quit and
// on the iPad in the background, where the memory limit is tightest. Here each
// type is collected on the main actor, encoded off it, and packed (LZ4) before
// the next type is collected; only one type's DTOs and NDJSON are alive at a
// time. The manifest must be the archive's first entry and needs every type's
// count, which is only known once that type is collected (the transformers
// skip malformed rows), so the packed entries wait in memory until the last
// type is done and are unpacked one at a time into the archive. The entries,
// their order and their bytes are exactly what `encodeAndWrite` writes.

import CoreData
import Foundation
import OSLog

nonisolated extension BackupWriter {

    /// How a streamed export ended.
    enum StreamedExport: Sendable {
        /// The archive is written, verified and in place.
        case written(BackupArchiveManifest)
        /// The view context held unsaved edits (or the two tables disagree),
        /// so nothing was collected.
        case declined
        /// Something changed while the types were being collected; nothing
        /// was written, and the collected rows were dropped.
        case abandoned
    }

    /// Where a streamed export goes and how it reports: `write`'s arguments,
    /// passed down as one value.
    struct ExportRequest: Sendable {
        let url: URL
        let deviceName: String
        let stopsWhenCancelled: Bool
        /// The note photos to carry, by filename (`BackupPhotos`).
        let photoNames: [String]
        let progress: BackupService.ProgressCallback
    }

    /// One entity type's rows, encoded and packed, waiting for the manifest.
    struct StagedEntity: Sendable {
        let entityName: String
        let count: Int
        /// The NDJSON's length before packing.
        let byteCount: Int
        /// The NDJSON, LZ4-compressed — or as is, if compression failed.
        let storage: Data
        let isCompressed: Bool

        /// The entity's NDJSON, exactly as encoded. Call inside an
        /// `autoreleasepool`: `NSData` hands back its buffers autoreleased, and
        /// the archive loop never returns to its thread's pool between entities.
        func ndjson() throws -> Data {
            guard isCompressed else { return storage }
            let unpacked = try (storage as NSData).decompressed(using: .lz4) as Data
            guard unpacked.count == byteCount else {
                throw WriterError.verificationFailed(
                    "\(entityName): staged \(byteCount) bytes, unpacked \(unpacked.count)"
                )
            }
            return unpacked
        }
    }

    /// Whether the collector table and the serialization table list the same
    /// entity types in the same order — the streamed export pairs them up row
    /// by row. A test pins it; if it ever fails in a build, the one-pass export
    /// (which reads each table on its own) runs instead of a mispaired one.
    @MainActor
    static var collectorsMatchSerializations: Bool {
        BackupService.entityCollectors.map(\.entityName) == serializedEntityNames
    }

    /// Collect → encode → pack, one entity type at a time, then write, verify
    /// and move the archive. Collection runs here on the main actor (the view
    /// context's queue); encoding runs in `stage` and the write in
    /// `writeStaged`, both off it.
    ///
    /// Between types the main actor runs other work, so `BackupSnapshotWatch`
    /// is asked after every type; on any change the export is abandoned before
    /// anything is written and `write` runs the one-pass export, whose single
    /// main-actor turn cannot see a change mid-way.
    @MainActor
    static func writeStreaming(
        service: BackupService,
        viewContext: NSManagedObjectContext,
        request: ExportRequest
    ) async throws -> StreamedExport {
        guard collectorsMatchSerializations else {
            Logger.backup.fault("Backup collector and serialization tables disagree; exporting in one pass")
            return .declined
        }
        guard let watch = BackupSnapshotWatch(viewContext: viewContext) else {
            Logger.backup.info("Exporting in one pass: the view context holds unsaved edits")
            return .declined
        }
        let preferences = service.buildPreferencesDTO()
        var staged: [StagedEntity] = []
        staged.reserveCapacity(entitySerializations.count)

        for (collector, serialization) in zip(BackupService.entityCollectors, entitySerializations) {
            // A stopping export ends here, between record types. Nothing has
            // been written yet, so there is nothing to remove.
            if request.stopsWhenCancelled { try Task.checkCancellation() }
            if let announcement = collector.announcement {
                let collecting = BackupProgress.progress(for: .collecting, subProgress: announcement.fraction)
                // The collector's 0-1 inner progress, mapped into the 0.0-0.6 outer band.
                request.progress(min(0.6, collecting * 0.6), announcement.message)
            }
            var slice = BackupPayload.collecting(preferences: preferences)
            collector.collect(service, viewContext, &slice)
            if watch.sawChange(in: viewContext) { return .abandoned }
            if let entity = try await stage(slice, as: serialization) {
                staged.append(entity)
            }
        }
        if watch.sawChangeAtEnd(in: viewContext) { return .abandoned }

        return .written(try await writeStaged(staged, preferences: preferences, request: request))
    }

    /// Encodes one entity type's DTOs as NDJSON — the same closure and encoder
    /// settings `encodeAndWrite` uses — and packs it. Nil for an empty type,
    /// which gets no entry. `@concurrent`: runs off the main actor.
    @concurrent
    static func stage(_ slice: BackupPayload, as serialization: EntitySerialization) async throws -> StagedEntity? {
        BackupPipelineProbe.reach("encode \(serialization.entityName)")
        let ndjson: Data?
        do {
            ndjson = try serialization.encode(slice, ndjsonEncoder())
        } catch {
            // An encode failure aborts the whole export, exactly as in the
            // one-pass export: the same rows would fail there too.
            throw WriterError.entityEncodingFailed(entityName: serialization.entityName, underlying: error)
        }
        guard let ndjson else { return nil }
        let count = serialization.count(slice)
        // LZ4 keeps about a third of this JSON's bytes and takes a few
        // milliseconds per 10 MB (2026-09-26, 22 ms to pack and 9 ms to unpack
        // 10.6 MB of note-shaped NDJSON on an M-series Mac).
        let packed = try? autoreleasepool { try (ndjson as NSData).compressed(using: .lz4) as Data }
        if let packed {
            return StagedEntity(
                entityName: serialization.entityName, count: count, byteCount: ndjson.count,
                storage: packed, isCompressed: true
            )
        }
        return StagedEntity(
            entityName: serialization.entityName, count: count, byteCount: ndjson.count,
            storage: ndjson, isCompressed: false
        )
    }

    /// Key, manifest, preferences, then each staged entry unpacked one at a
    /// time into the archive; verify; move. The progress lines match
    /// `encodeAndWrite`'s. `@concurrent`: runs off the main actor.
    @concurrent
    static func writeStaged(
        _ staged: [StagedEntity],
        preferences: PreferencesDTO,
        request: ExportRequest
    ) async throws -> BackupArchiveManifest {
        BackupPipelineProbe.reach("write staged")
        let stopsWhenCancelled = request.stopsWhenCancelled
        let progress = request.progress
        if stopsWhenCancelled { try Task.checkCancellation() }
        // SecItemCopyMatching blocks its thread on a round trip to securityd,
        // which Apple says to keep off the main thread.
        let encryptionKey = try BackupEncryptionKeyStore.fetchOrCreateKey()
        await progress(0.65, "Encoding\u{2026}")
        let photos = BackupPhotos.localFiles(for: request.photoNames)
        let manifest = makeManifest(
            counts: staged.map { ($0.entityName, $0.count) },
            deviceName: request.deviceName,
            photoCount: photos.count
        )
        let job = ArchiveJob(
            manifest: manifest,
            manifestData: try encodeManifest(manifest),
            preferencesData: try preferences.archiveJSON(),
            encryptionKey: encryptionKey,
            url: request.url,
            stopsWhenCancelled: stopsWhenCancelled,
            photos: photos
        )

        await progress(0.75, "Writing archive\u{2026}")
        let writtenEntryCount = try await writeVerifiedArchive(job, progress: progress) { appender in
            for entity in staged {
                // A stopping export ends here too, between record types; the
                // helper removes what was written so far.
                if stopsWhenCancelled { try Task.checkCancellation() }
                // One entity's unpacked bytes at a time: the pool drains here,
                // not when the whole archive is written.
                try autoreleasepool {
                    try appender.append(path: archivePath(for: entity.entityName), data: try entity.ndjson())
                }
            }
            return staged.count
        }

        await progress(1.0, "Backup complete")
        let packed = staged.reduce(0) { $0 + $1.storage.count }
        let raw = staged.reduce(0) { $0 + $1.byteCount }
        let writeMsg = "BackupWriter streamed and verified v\(formatVersion) backup with " +
            "\(writtenEntryCount) entity entries (\(raw) NDJSON bytes staged as \(packed))"
        Logger.backup.info("\(writeMsg, privacy: .public)")
        return manifest
    }
}
