// BackupWriter.swift
// Builds a v19 encrypted backup file from a Core Data context.
//
// Reuses `BackupService.collectPayload(viewContext:progress:)` for the
// per-entity DTO transformer logic (same code path the legacy export used).
// Adds:
//   - Manifest entry (`manifest.json`) written first, with format version,
//     entity counts, app version/build, device name, and origin-store routing.
//   - One NDJSON entry per non-empty entity array, named
//     `<store>/<EntityName>.ndjson` so the importer can route to the right
//     persistent store on the destination device.
//   - Preferences entry (`preferences.json`) for the app's user-defined
//     settings dictionary.
//
// Write pipeline (all off the main actor after payload collection):
//   serialize → manifest → write encrypted archive to a hidden temp file in
//   the destination directory → re-read and verify structure + counts →
//   atomically move into place. A failed export can therefore never leave a
//   truncated or unverified file at the destination, and an encode failure
//   for any entity type aborts the export instead of silently dropping data.

import Foundation
import CoreData
import CryptoKit
import OSLog
#if canImport(UIKit)
import UIKit
#endif

public enum BackupWriter {
    private static let logger = Logger.backup

    /// Format version produced by this writer.
    /// - v19: Apple Encrypted Archive container ("AA01" magic) — AES-CTR+HMAC
    ///   with the iCloud-Keychain symmetric key; LZFSE inside the AEA layer.
    /// - v20: Adds backup coverage for CDGuardian and CDParentCommunication.
    ///   Purely additive NDJSON entries.
    ///   Entry layout is unchanged from v18, so v17/v18 readers of the
    ///   decrypted stream need no changes.
    /// - v18: Adds backup coverage for CDDayPad, CDYearPlanEntry,
    ///   CDLessonSequenceSettings, CDStory, CDBookClubPacket, CDBookClubSession,
    ///   CDBookClubMeeting. Purely additive NDJSON entries.
    /// - v17: AppleArchive-framed NDJSON (replaced the legacy v16 JSON envelope).
    public static let formatVersion: Int = 21

    public enum WriterError: LocalizedError {
        case entityEncodingFailed(entityName: String, underlying: Error)
        case verificationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .entityEncodingFailed(let entityName, let underlying):
                return "Backup aborted: could not encode \(entityName) records " +
                    "(\(underlying.localizedDescription)). No file was written \u{2014} " +
                    "a backup silently missing \(entityName) data would be worse than no backup."
            case .verificationFailed(let reason):
                return "Backup aborted: the written file failed read-back verification (\(reason)). " +
                    "No file was saved to the destination."
            }
        }
    }

    // MARK: - Public API

    /// Builds a v19 backup at `url`. Caller must hold the security-scoped
    /// resource (if any) for `url`.
    ///
    /// Payload collection runs on the main actor (Core Data's queue for the
    /// view context); encoding, encryption, writing, and verification all run
    /// off the main actor so the UI stays responsive during export.
    @MainActor
    @discardableResult
    public static func write(
        viewContext: NSManagedObjectContext,
        to url: URL,
        progress: @escaping BackupService.ProgressCallback = { _, _ in }
    ) async throws -> BackupOperationSummary {
        progress(0.0, "Collecting entities\u{2026}")

        // Reuse the shared collector — the same transformer code path that's
        // been shipping. Collection must stay on the view context's queue.
        let backupService = BackupService()
        let payload = backupService.collectPayload(viewContext: viewContext) { sub, message in
            // Map the collector's 0-1 inner progress into the 0.0-0.6 outer band.
            progress(min(0.6, sub * 0.6), message)
        }

        let deviceName = currentDeviceName()
        let encryptionKey = try BackupEncryptionKeyStore.fetchOrCreateKey()

        let manifest = try await encodeAndWrite(
            payload: payload,
            deviceName: deviceName,
            encryptionKey: encryptionKey,
            to: url,
            progress: progress
        )

        return BackupOperationSummary(
            kind: .export,
            fileName: url.lastPathComponent,
            formatVersion: formatVersion,
            encryptUsed: true,
            createdAt: Date(),
            entityCounts: manifest.entityCounts,
            warnings: ["Imported documents and file attachments are not included in backups by design."]
        )
    }

    // MARK: - Off-Main Pipeline

    /// Encode, write, verify, move. `nonisolated async` so it runs on the
    /// global executor, not the main actor — this is the CPU/IO-heavy part.
    private static func encodeAndWrite(
        payload: BackupPayload,
        deviceName: String,
        encryptionKey: SymmetricKey,
        to url: URL,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupArchiveManifest {
        await progress(0.65, "Encoding\u{2026}")
        // The manifest needs per-entity counts and store routing — not the encoded
        // bytes — so it can be built before anything is serialized. That's what
        // lets the loop below encode one entity at a time: previously every
        // entity's NDJSON was materialized up front and held alongside the full
        // DTO graph, which put the export's peak at roughly two copies of the
        // database, at app quit / iOS background where the jetsam limit is
        // tightest. Output bytes are identical.
        let manifest = buildManifest(payload: payload, deviceName: deviceName)
        let manifestData = try encodeManifest(manifest)
        let preferencesData = try payload.preferencesJSON()

        await progress(0.75, "Writing archive\u{2026}")
        // Hidden temp file in the destination directory (same volume, so the
        // final move is an atomic rename — also under any security scope the
        // caller holds for that folder).
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).partial-\(UUID().uuidString)")

        var writtenEntryCount = 0
        do {
            let encoder = ndjsonEncoder()
            try BackupArchive.write(to: tempURL, encryptionKey: encryptionKey) { appender in
                // Manifest first so readers can stream-validate.
                try appender.append(path: "manifest.json", data: manifestData)
                // Preferences as a single JSON document (not NDJSON).
                try appender.append(path: "preferences.json", data: preferencesData)
                // Then each non-empty entity entry, in registry order. Encoding
                // happens here so each entity's bytes are released before the next
                // one is built.
                for serialization in entitySerializations {
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
                    writtenEntryCount += 1
                }
            }

            await progress(0.9, "Verifying\u{2026}")
            try verifyWrittenArchive(at: tempURL, encryptionKey: encryptionKey, expected: manifest)
            try moveIntoPlace(from: tempURL, to: url)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        await progress(1.0, "Backup complete")
        let writeMsg = "BackupWriter wrote and verified v\(formatVersion) backup " +
            "with \(writtenEntryCount) entity entries"
        logger.info("\(writeMsg, privacy: .public)")
        return manifest
    }

    /// Re-reads the just-written archive and checks that the manifest decodes
    /// to what was intended and every entity entry holds exactly the promised
    /// number of NDJSON rows. Catches truncation, encode bugs, and disk-level
    /// corruption before the file ever reaches the destination.
    private static func verifyWrittenArchive(
        at url: URL,
        encryptionKey: SymmetricKey,
        expected: BackupArchiveManifest
    ) throws {
        let verification = try BackupReader.verifyStructure(at: url) { encryptionKey }

        guard verification.manifest.formatVersion == expected.formatVersion,
              verification.manifest.entityCounts == expected.entityCounts,
              verification.manifest.originStores == expected.originStores else {
            throw WriterError.verificationFailed("manifest did not round-trip")
        }
        for (entityName, expectedCount) in expected.entityCounts {
            let actual = verification.entryLineCounts[entityName] ?? 0
            guard actual == expectedCount else {
                throw WriterError.verificationFailed(
                    "\(entityName): wrote \(expectedCount) records, read back \(actual)"
                )
            }
        }
    }

    private static func moveIntoPlace(from tempURL: URL, to url: URL) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.moveItem(at: tempURL, to: url)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
        }
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
    private static func serialization<T: Encodable & Sendable>(
        _ entityName: String,
        _ select: @escaping @Sendable (BackupPayload) -> [T]
    ) -> EntitySerialization {
        EntitySerialization(
            entityName: entityName,
            count: { select($0).count },
            encode: { payload, encoder in try ndjsonData(select(payload), encoder) }
        )
    }

    static let entitySerializations: [EntitySerialization] = [
        // Core (required arrays)
        serialization("Student") { $0.students },
        serialization("Lesson") { $0.lessons },
        serialization("LessonAssignment") { $0.lessonAssignments },
        serialization("Note") { $0.notes },
        serialization("NonSchoolDay") { $0.nonSchoolDays },
        serialization("SchoolDayOverride") { $0.schoolDayOverrides },
        serialization("StudentMeeting") { $0.studentMeetings },
        serialization("CommunityTopic") { $0.communityTopics },
        serialization("ProposedSolution") { $0.proposedSolutions },
        serialization("CommunityAttachment") { $0.communityAttachments },
        serialization("AttendanceRecord") { $0.attendance },
        serialization("WorkCompletionRecord") { $0.workCompletions },
        serialization("Project") { $0.projects },
        serialization("ProjectSession") { $0.projectSessions },
        serialization("ProjectRole") { $0.projectRoles },

        // Optional arrays (v8+ extensions)
        serialization("WorkModel") { $0.workModels ?? [] },
        serialization("WorkCheckIn") { $0.workCheckIns ?? [] },
        serialization("WorkStep") { $0.workSteps ?? [] },
        serialization("WorkParticipantEntity") { $0.workParticipants ?? [] },
        serialization("PracticeSession") { $0.practiceSessions ?? [] },
        serialization("LessonAttachment") { $0.lessonAttachments ?? [] },
        serialization("LessonPresentation") { $0.lessonPresentations ?? [] },
        serialization("LessonRecallCheck") { $0.recallChecks ?? [] },
        serialization("SampleWork") { $0.sampleWorks ?? [] },
        serialization("SampleWorkStep") { $0.sampleWorkSteps ?? [] },
        serialization("NoteTemplate") { $0.noteTemplates ?? [] },
        serialization("MeetingTemplate") { $0.meetingTemplates ?? [] },
        serialization("Reminder") { $0.reminders ?? [] },
        serialization("CalendarEvent") { $0.calendarEvents ?? [] },
        serialization("Track") { $0.tracks ?? [] },
        serialization("TrackStep") { $0.trackSteps ?? [] },
        serialization("StudentTrackEnrollment") { $0.studentTrackEnrollments ?? [] },
        serialization("SequenceTrack") { $0.sequenceTracks ?? [] },
        serialization("Document") { $0.documents ?? [] },
        serialization("Supply") { $0.supplies ?? [] },
        serialization("Procedure") { $0.procedures ?? [] },
        serialization("Schedule") { $0.schedules ?? [] },
        serialization("ScheduleSlot") { $0.scheduleSlots ?? [] },
        serialization("Issue") { $0.issues ?? [] },
        serialization("IssueAction") { $0.issueActions ?? [] },
        serialization("DevelopmentSnapshot") { $0.developmentSnapshots ?? [] },
        serialization("TodoItem") { $0.todoItems ?? [] },
        serialization("TodoSubtask") { $0.todoSubtasks ?? [] },
        serialization("TodoTemplate") { $0.todoTemplates ?? [] },
        serialization("TodayAgendaOrder") { $0.todayAgendaOrders ?? [] },
        serialization("PlanningRecommendation") { $0.planningRecommendations ?? [] },
        serialization("Resource") { $0.resources ?? [] },
        serialization("NoteStudentLink") { $0.noteStudentLinks ?? [] },
        serialization("GoingOut") { $0.goingOuts ?? [] },
        serialization("GoingOutChecklistItem") { $0.goingOutChecklistItems ?? [] },
        serialization("ClassroomJob") { $0.classroomJobs ?? [] },
        serialization("JobAssignment") { $0.jobAssignments ?? [] },
        serialization("CalendarNote") { $0.calendarNotes ?? [] },
        serialization("ScheduledMeeting") { $0.scheduledMeetings ?? [] },
        serialization("ClassroomMembership") { $0.classroomMemberships ?? [] },
        serialization("MeetingWorkReview") { $0.meetingWorkReviews ?? [] },
        serialization("StudentFocusItem") { $0.studentFocusItems ?? [] },

        // Format v18+ extensions
        serialization("DayPad") { $0.dayPads ?? [] },
        serialization("YearPlanEntry") { $0.yearPlanEntries ?? [] },
        serialization("LessonSequenceSettings") { $0.lessonSequenceSettings ?? [] },
        serialization("Story") { $0.stories ?? [] },
        serialization("BookClubPacket") { $0.bookClubPackets ?? [] },
        serialization("BookClubSession") { $0.bookClubSessions ?? [] },
        serialization("BookClubMeeting") { $0.bookClubMeetings ?? [] },

        // Format v20+ extensions
        serialization("Guardian") { $0.guardians ?? [] },
        serialization("ParentCommunication") { $0.parentCommunications ?? [] },

        // Format v21+ extensions — teaching-album annotations
        serialization("AlbumBookmark") { $0.albumBookmarks ?? [] },
        serialization("AlbumPageNote") { $0.albumPageNotes ?? [] },
        serialization("AlbumRecentVisit") { $0.albumRecentVisits ?? [] },
        serialization("AlbumReadingPosition") { $0.albumReadingPositions ?? [] },
        serialization("AlbumHighlight") { $0.albumHighlights ?? [] },
        serialization("AlbumPageInk") { $0.albumPageInk ?? [] }
    ]

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
    private static func archivePath(for entityName: String) -> String {
        "\(store(for: entityName))/\(entityName).ndjson"
    }

    // MARK: - Manifest

    /// Built straight from the payload's array counts, before any encoding — the
    /// manifest never needed the encoded bytes, only how many rows each entity has
    /// and which store it came from. Only non-empty entities are listed, matching
    /// the entries actually written.
    private static func buildManifest(
        payload: BackupPayload,
        deviceName: String
    ) -> BackupArchiveManifest {
        var counts: [String: Int] = [:]
        var stores: [String: String] = [:]
        for serialization in entitySerializations {
            let count = serialization.count(payload)
            guard count > 0 else { continue }
            counts[serialization.entityName] = count
            stores[serialization.entityName] = store(for: serialization.entityName)
        }
        return BackupArchiveManifest(
            formatVersion: formatVersion,
            createdAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            device: deviceName,
            entityCounts: counts,
            originStores: stores
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

    private static func encodeManifest(_ manifest: BackupArchiveManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }

    // MARK: - NDJSON Encoding

    private static func ndjsonEncoder() -> JSONEncoder {
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
public struct BackupArchiveManifest: Codable, Sendable, Equatable {
    public var formatVersion: Int
    public var createdAt: Date
    public var appVersion: String
    public var appBuild: String
    public var device: String
    public var entityCounts: [String: Int]
    public var originStores: [String: String]
}

// MARK: - Entry Type

/// One in-archive entity entry. NDJSON body holds one DTO per line.
/// Shared between `BackupWriter` (produces entries) and `BackupReader`/
/// `BackupImporter` (consume entries).
public struct BackupEntityEntry: Sendable {
    public let entityName: String
    public let storeName: String     // "private" or "shared"
    public let count: Int
    public let ndjson: Data
    public var archivePath: String { "\(storeName)/\(entityName).ndjson" }

    public init(entityName: String, storeName: String, count: Int, ndjson: Data) {
        self.entityName = entityName
        self.storeName = storeName
        self.count = count
        self.ndjson = ndjson
    }
}

// MARK: - Preferences serialization

private extension BackupPayload {
    /// Encodes the preferences dictionary as a single JSON document
    /// (preferences are small, so we don't bother with NDJSON for them).
    func preferencesJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(preferences)
    }
}
