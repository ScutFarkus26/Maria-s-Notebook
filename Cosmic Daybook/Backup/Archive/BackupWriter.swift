// BackupWriter.swift
// Builds a v19 encrypted backup file from a Core Data context.
//
// Collection uses `BackupService.entityCollectors` (the per-entity DTO
// transformer table `collectPayload` also runs). The archive holds:
//   - Manifest entry (`manifest.json`) written first, with format version,
//     entity counts, app version/build, device name, and origin-store routing.
//   - Preferences entry (`preferences.json`) for the app's user-defined
//     settings dictionary.
//   - One NDJSON entry per non-empty entity array, named
//     `<store>/<EntityName>.ndjson` so the importer can route to the right
//     persistent store on the destination device.
//
// Two ways to the same bytes. The streamed export (`BackupWriter+Streaming`)
// collects one entity type on the main actor, encodes it off the main actor,
// and packs it before collecting the next, so the whole database never sits
// in memory as DTOs. The one-pass export (`encodeAndWrite`) collects every
// type first; it runs when the view context holds unsaved edits or when
// something changed mid-stream (`BackupSnapshotWatch`).
//
// Either way the write ends the same: encrypted archive to a hidden temp file
// in the destination directory → re-read and verify structure + counts →
// atomically move into place (`writeVerifiedArchive`). A failed export can
// therefore never leave a truncated or unverified file at the destination,
// and an encode failure for any entity type aborts the export instead of
// silently dropping data.

import Foundation
import CoreData
import CryptoKit
import OSLog
#if canImport(UIKit)
import UIKit
#endif

nonisolated public enum BackupWriter {
    private static let logger = Logger.backup

    /// Format version produced by this writer.
    /// - v19: Apple Encrypted Archive container ("AA01" magic) — AES-CTR+HMAC
    ///   with the iCloud-Keychain symmetric key; LZFSE inside the AEA layer.
    /// - v25: `Lesson` entries carry `isKeyLesson`, the Three-Year View's
    ///   milestone flag. Purely additive; entry layout is otherwise unchanged.
    /// - v24: `ScheduledMeeting` entries carry `purpose`. Purely additive;
    ///   entry layout is otherwise unchanged.
    /// - v26: `WorkModel.statusRaw` may carry the merged vocabulary
    ///   (`mastered`, `keepPracticing`, `incomplete`) alongside the old
    ///   `active` / `review` / `complete`; `completionOutcomeRaw` is still
    ///   written but is legacy. Entry layout is unchanged.
    /// - v27: Adds backup coverage for CDOrderItem (the Orders list) and the
    ///   `Orders.*` request preferences. Purely additive.
    /// - v23: Preferences entry grows from 15 keys to the full set of
    ///   user-chosen settings (school year, recall, AI models, view state,
    ///   per-date attendance locks, album folder bookmarks + fingerprints) and
    ///   gains a `plist` value type for list/map preferences. Entity entries
    ///   are unchanged.
    /// - v20: Adds backup coverage for CDGuardian and CDParentCommunication.
    ///   Purely additive NDJSON entries.
    ///   Entry layout is unchanged from v18, so v17/v18 readers of the
    ///   decrypted stream need no changes.
    /// - v18: Adds backup coverage for CDDayPad, CDYearPlanEntry,
    ///   CDLessonSequenceSettings, CDStory, CDBookClubPacket, CDBookClubSession,
    ///   CDBookClubMeeting. Purely additive NDJSON entries.
    /// - v17: AppleArchive-framed NDJSON (replaced the legacy v16 JSON envelope).
    /// - v28: Note photos ride along as `photos/<filename>` entries after the
    ///   entity entries, counted in the manifest's `photoCount`
    ///   (`BackupPhotos`). Entity entries are unchanged; a v27 reader rejects
    ///   the new paths, hence the version.
    /// - v29: `AttendanceRecord` entries carry `note`, the day's attendance
    ///   note, which moved off the private notes onto the shared record.
    ///   Purely additive; entry layout is otherwise unchanged.
    public static let formatVersion: Int = 29

    public enum WriterError: LocalizedError {
        case entityEncodingFailed(entityName: String, underlying: Error)
        case verificationFailed(String)
        case photoUnreadable(filename: String, underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .entityEncodingFailed(let entityName, let underlying):
                return "Backup aborted: could not encode \(entityName) records " +
                    "(\(underlying.localizedDescription)). No file was written \u{2014} " +
                    "a backup silently missing \(entityName) data would be worse than no backup."
            case .verificationFailed(let reason):
                return "Backup aborted: the written file failed read-back verification (\(reason)). " +
                    "No file was saved to the destination."
            case .photoUnreadable(let filename, let underlying):
                return "Backup aborted: the note photo \(filename) could not be read " +
                    "(\(underlying.localizedDescription)). No file was written."
            }
        }
    }

    // MARK: - Public API

    /// Builds a v19 backup at `url`. Caller must hold the security-scoped
    /// resource (if any) for `url`.
    ///
    /// Collection runs on the main actor (Core Data's queue for the view
    /// context); the Keychain read, encoding, encryption, writing, and
    /// verification all run off the main actor (`@concurrent`) so the UI stays
    /// responsive during export. The streamed export is tried first; see the
    /// file header for when the one-pass export runs instead.
    ///
    /// `stopsWhenCancelled` is for the iPad's overnight background task only.
    /// That export checks its task before collecting, between record types,
    /// and before verifying, and once iPadOS has ended the task it throws
    /// `CancellationError` there, leaving nothing at `url` (the hidden temp
    /// file is removed). Every other export runs to the end even if its task
    /// is cancelled.
    ///
    /// `includesPhotos` adds the note photos (`BackupPhotos`); nil follows the
    /// guide's setting, and the pre-restore checkpoint passes false.
    @MainActor
    @discardableResult
    public static func write(
        viewContext: NSManagedObjectContext,
        to url: URL,
        stopsWhenCancelled: Bool = false,
        includesPhotos: Bool? = nil,
        progress: @escaping BackupService.ProgressCallback = { _, _ in }
    ) async throws -> BackupOperationSummary {
        if stopsWhenCancelled { try Task.checkCancellation() }
        progress(0.0, "Collecting entities\u{2026}")

        // Collection must stay on the view context's queue.
        BackupPipelineProbe.reach("collect")
        let backupService = BackupService()
        let deviceName = currentDeviceName()
        // Names only, read here on the view context's queue; the files are
        // found and read off the main actor.
        let includesPhotos = includesPhotos ?? BackupPhotos.includesNotePhotos
        let photoNames = includesPhotos ? BackupPhotos.referencedFilenames(in: viewContext) : []

        let manifest: BackupArchiveManifest
        let streamed = try await writeStreaming(
            service: backupService,
            viewContext: viewContext,
            request: ExportRequest(
                url: url, deviceName: deviceName, stopsWhenCancelled: stopsWhenCancelled,
                photoNames: photoNames, progress: progress
            )
        )
        if case .written(let written) = streamed {
            manifest = written
        } else {
            // One pass: every type in this main-actor turn, then encoded off it.
            // After an abandoned stream its collection progress was already
            // shown, so the second collection runs silently.
            var reportsCollection = true
            if case .abandoned = streamed {
                reportsCollection = false
                logger.info("Exporting in one pass: the notebook changed while the export streamed")
                if stopsWhenCancelled { try Task.checkCancellation() }
                BackupPipelineProbe.reach("collect in one pass")
            }
            let payload = backupService.collectPayload(viewContext: viewContext) { [reportsCollection] sub, message in
                // Map the collector's 0-1 inner progress into the 0.0-0.6 outer band.
                if reportsCollection { progress(min(0.6, sub * 0.6), message) }
            }
            manifest = try await encodeAndWrite(
                payload: payload,
                deviceName: deviceName,
                to: url,
                stopsWhenCancelled: stopsWhenCancelled,
                photoNames: photoNames,
                progress: progress
            )
        }

        return BackupOperationSummary(
            kind: .export,
            fileName: url.lastPathComponent,
            formatVersion: formatVersion,
            encryptUsed: true,
            createdAt: Date(),
            entityCounts: manifest.entityCounts,
            warnings: [includesPhotos
                ? "Note photos are included (\(manifest.photoCount ?? 0)); imported documents and "
                    + "file attachments are not, by design."
                : "Note photos, imported documents and file attachments are not included in this backup."]
        )
    }

    // MARK: - Off-Main Pipeline

    /// Key, encode, encrypt, write, verify, move: the CPU- and IO-heavy half
    /// of the one-pass export. `@concurrent`, so it runs on the global executor
    /// at the calling task's priority. A plain `nonisolated async` function
    /// would run on its caller's actor under NonisolatedNonsendingByDefault, and
    /// every caller is main-actor code: until 2026-09-25 this all ran on the
    /// main thread. Internal so tests can hand it a fixed payload.
    @concurrent
    static func encodeAndWrite(
        payload: BackupPayload,
        deviceName: String,
        to url: URL,
        stopsWhenCancelled: Bool = false,
        photoNames: [String] = [],
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupArchiveManifest {
        // Collection held the main actor; the task may have been ended meanwhile.
        if stopsWhenCancelled { try Task.checkCancellation() }
        // SecItemCopyMatching blocks its thread on a round trip to securityd,
        // which Apple says to keep off the main thread.
        let encryptionKey = try BackupEncryptionKeyStore.fetchOrCreateKey()
        await progress(0.65, "Encoding\u{2026}")
        // The manifest needs per-entity counts and store routing — not the encoded
        // bytes — so it can be built before anything is serialized. That's what
        // lets the loop below encode one entity at a time: previously every
        // entity's NDJSON was materialized up front and held alongside the full
        // DTO graph, which put the export's peak at roughly two copies of the
        // database, at app quit / iOS background where the jetsam limit is
        // tightest. Output bytes are identical.
        let photos = BackupPhotos.localFiles(for: photoNames)
        let manifest = makeManifest(
            counts: entitySerializations.map { ($0.entityName, $0.count(payload)) },
            deviceName: deviceName,
            photoCount: photos.count
        )
        let job = ArchiveJob(
            manifest: manifest,
            manifestData: try encodeManifest(manifest),
            preferencesData: try payload.preferences.archiveJSON(),
            encryptionKey: encryptionKey,
            url: url,
            stopsWhenCancelled: stopsWhenCancelled,
            photos: photos
        )

        await progress(0.75, "Writing archive\u{2026}")
        let writtenEntryCount = try await writeVerifiedArchive(job, progress: progress) { appender in
            // Each non-empty entity entry, in registry order. Encoding happens
            // here so each entity's bytes are released before the next one is built.
            let encoder = ndjsonEncoder()
            var written = 0
            for serialization in entitySerializations {
                // A stopping export ends here, between record types; the
                // helper removes what was written so far.
                if stopsWhenCancelled { try Task.checkCancellation() }
                BackupPipelineProbe.reach("encode \(serialization.entityName)")
                let ndjson: Data?
                do {
                    ndjson = try serialization.encode(payload, encoder)
                } catch {
                    // An encode failure aborts the whole export — a backup that
                    // silently omits an entity type would verify clean and read
                    // back as data loss months later.
                    throw WriterError.entityEncodingFailed(
                        entityName: serialization.entityName,
                        underlying: error
                    )
                }
                guard let ndjson else { continue }
                try appender.append(
                    path: archivePath(for: serialization.entityName),
                    data: ndjson
                )
                written += 1
            }
            return written
        }

        await progress(1.0, "Backup complete")
        let writeMsg = "BackupWriter wrote and verified v\(formatVersion) backup " +
            "with \(writtenEntryCount) entity entries"
        logger.info("\(writeMsg, privacy: .public)")
        return manifest
    }

    // MARK: - Entry Serialization

    /// One row per backed-up entity type: the archive entry name plus a
    /// closure that encodes that type's DTO array out of a payload. This
    /// table is the writer's single list — `serializedEntityNames` feeds the
    /// coverage test that keeps it in sync with `BackupEntityRegistry`.
    struct EntitySerialization: Sendable {
        let entityName: String
        /// Row count without encoding anything — the manifest needs counts, not
        /// bytes, so it can be built before serialization starts.
        let count: @Sendable (BackupPayload) -> Int
        /// This entity's DTO array as NDJSON. `nil` for an empty array, so the
        /// archive only carries non-empty entries.
        let encode: @Sendable (BackupPayload, JSONEncoder) throws -> Data?
    }

    /// Builds one row of the table from a payload accessor, so the count pass and
    /// the encode pass can never disagree about which array an entity maps to.
    static func serialization<T: Encodable & Sendable>(
        _ entityName: String,
        _ select: @escaping @Sendable (BackupPayload) -> [T]
    ) -> EntitySerialization {
        EntitySerialization(
            entityName: entityName,
            count: { select($0).count },
            encode: { payload, encoder in try ndjsonData(select(payload), encoder) }
        )
    }

    /// The writer's rows, from `BackupEntityTable`, in archive order.
    static let entitySerializations: [EntitySerialization] = BackupEntityTable.entities.map(\.serialization)

    /// Every entity name this writer can serialize, in archive order. The
    /// coverage tests compare this against `BackupEntityRegistry`.
    public static var serializedEntityNames: [String] {
        entitySerializations.map(\.entityName)
    }

    /// Materializes every entity entry at once. The export path deliberately does
    /// *not* use this — it encodes and appends one entity at a time so peak memory
    /// stays at a single entity rather than the whole database. Kept for tests and
    /// callers that need the entries as values.
    ///
    /// An encode failure here aborts the whole export (wrapped in
    /// `WriterError.entityEncodingFailed`) — a backup that silently omits an
    /// entity type would verify clean and read back as data loss months later.
    static func serializeEntries(from payload: BackupPayload) throws -> [BackupEntityEntry] {
        let encoder = ndjsonEncoder()
        var entries: [BackupEntityEntry] = []
        entries.reserveCapacity(entitySerializations.count)

        for serialization in entitySerializations {
            do {
                guard let ndjson = try serialization.encode(payload, encoder) else { continue }
                entries.append(BackupEntityEntry(
                    entityName: serialization.entityName,
                    storeName: store(for: serialization.entityName),
                    count: serialization.count(payload),
                    ndjson: ndjson
                ))
            } catch {
                throw WriterError.entityEncodingFailed(
                    entityName: serialization.entityName,
                    underlying: error
                )
            }
        }
        return entries
    }

    /// Encodes a DTO array as NDJSON. Returns nil for an empty array so the
    /// archive only carries non-empty entries.
    private static func ndjsonData<T: Encodable>(
        _ dtos: [T],
        _ encoder: JSONEncoder
    ) throws -> Data? {
        guard !dtos.isEmpty else { return nil }
        var buffer = Data()
        let newline = Data([0x0A])
        for dto in dtos {
            let line = try encoder.encode(dto)
            buffer.append(line)
            buffer.append(newline)
        }
        return buffer
    }

    /// In-archive path for an entity entry. Must match `BackupEntityEntry.archivePath`.
    static func archivePath(for entityName: String) -> String {
        "\(store(for: entityName))/\(entityName).ndjson"
    }

    // MARK: - Manifest

    /// Built from per-entity row counts, before any entity entry is written —
    /// the manifest never needed the encoded bytes, only how many rows each
    /// entity has and which store it came from. Only non-empty entities are
    /// listed, matching the entries actually written.
    static func makeManifest(
        counts: [(entityName: String, count: Int)],
        deviceName: String,
        photoCount: Int = 0
    ) -> BackupArchiveManifest {
        var entityCounts: [String: Int] = [:]
        var stores: [String: String] = [:]
        for (entityName, count) in counts where count > 0 {
            entityCounts[entityName] = count
            stores[entityName] = store(for: entityName)
        }
        return BackupArchiveManifest(
            formatVersion: formatVersion,
            createdAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            device: deviceName,
            entityCounts: entityCounts,
            originStores: stores,
            photoCount: photoCount > 0 ? photoCount : nil
        )
    }

    /// The user-visible device name, without `ProcessInfo.hostName` — that
    /// API can block on a reverse-DNS lookup, which is unacceptable on the
    /// main actor where this runs.
    @MainActor
    private static func currentDeviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return ProcessInfo.processInfo.processName
        #endif
    }

    static func encodeManifest(_ manifest: BackupArchiveManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }

    // MARK: - NDJSON Encoding

    static func ndjsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Sorted keys for deterministic output (helpful for diffing). No pretty-printing
        // inside NDJSON entries — each line is one JSON object.
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: - Store Routing

    /// Returns "private" or "shared" for the given entity name.
    /// Mirrors `CoreDataStack.sharedEntityNames` — the canonical source of truth.
    static func store(for entityName: String) -> String {
        CoreDataStack.sharedEntityNames.contains(entityName) ? "shared" : "private"
    }
}

// MARK: - Manifest Type

/// JSON-encoded into the archive's first entry. Read by `BackupReader` before
/// any entity data so import can validate version + routing up front.
nonisolated public struct BackupArchiveManifest: Codable, Sendable, Equatable {
    public var formatVersion: Int
    public var createdAt: Date
    public var appVersion: String
    public var appBuild: String
    public var device: String
    public var entityCounts: [String: Int]
    public var originStores: [String: String]
    /// How many note photo entries follow the entity entries (v28+); absent
    /// when there are none, so a photo-less manifest encodes as before.
    public var photoCount: Int? = nil
}

// MARK: - Entry Type

/// One in-archive entity entry. NDJSON body holds one DTO per line.
/// Shared between `BackupWriter` (produces entries) and `BackupReader`/
/// `BackupImporter` (consume entries).
nonisolated public struct BackupEntityEntry: Sendable {
    public let entityName: String
    public let storeName: String     // "private" or "shared"
    public let count: Int
    public let ndjson: Data

    public init(entityName: String, storeName: String, count: Int, ndjson: Data) {
        self.entityName = entityName
        self.storeName = storeName
        self.count = count
        self.ndjson = ndjson
    }
}
