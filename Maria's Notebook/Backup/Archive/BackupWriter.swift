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
    ///   Entry layout is unchanged from v18, so v17/v18 readers of the
    ///   decrypted stream need no changes.
    /// - v18: Adds backup coverage for CDDayPad, CDYearPlanEntry,
    ///   CDLessonSequenceSettings, CDStory, CDBookClubPacket, CDBookClubSession,
    ///   CDBookClubMeeting. Purely additive NDJSON entries.
    /// - v17: AppleArchive-framed NDJSON (replaced the legacy v16 JSON envelope).
    public static let formatVersion: Int = 19

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
        let entries = try serializeEntries(from: payload)
        let manifest = buildManifest(entries: entries, deviceName: deviceName)
        let manifestData = try encodeManifest(manifest)
        let preferencesData = try payload.preferencesJSON()

        await progress(0.75, "Writing archive\u{2026}")
        // Hidden temp file in the destination directory (same volume, so the
        // final move is an atomic rename — also under any security scope the
        // caller holds for that folder).
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).partial-\(UUID().uuidString)")

        do {
            try BackupArchive.write(to: tempURL, encryptionKey: encryptionKey) { appender in
                // Manifest first so readers can stream-validate.
                try appender.append(path: "manifest.json", data: manifestData)
                // Preferences as a single JSON document (not NDJSON).
                try appender.append(path: "preferences.json", data: preferencesData)
                // Then each non-empty entity entry, in registry order.
                for entry in entries {
                    try appender.append(path: entry.archivePath, data: entry.ndjson)
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
            "with \(entries.count) entity entries"
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
        let encode: @Sendable (BackupPayload, JSONEncoder) throws -> (ndjson: Data, count: Int)?
    }

    static let entitySerializations: [EntitySerialization] = [
        // Core (required arrays)
        .init(entityName: "Student") { try ndjsonEntry($0.students, $1) },
        .init(entityName: "Lesson") { try ndjsonEntry($0.lessons, $1) },
        .init(entityName: "LessonAssignment") { try ndjsonEntry($0.lessonAssignments, $1) },
        .init(entityName: "Note") { try ndjsonEntry($0.notes, $1) },
        .init(entityName: "NonSchoolDay") { try ndjsonEntry($0.nonSchoolDays, $1) },
        .init(entityName: "SchoolDayOverride") { try ndjsonEntry($0.schoolDayOverrides, $1) },
        .init(entityName: "StudentMeeting") { try ndjsonEntry($0.studentMeetings, $1) },
        .init(entityName: "CommunityTopic") { try ndjsonEntry($0.communityTopics, $1) },
        .init(entityName: "ProposedSolution") { try ndjsonEntry($0.proposedSolutions, $1) },
        .init(entityName: "CommunityAttachment") { try ndjsonEntry($0.communityAttachments, $1) },
        .init(entityName: "AttendanceRecord") { try ndjsonEntry($0.attendance, $1) },
        .init(entityName: "WorkCompletionRecord") { try ndjsonEntry($0.workCompletions, $1) },
        .init(entityName: "Project") { try ndjsonEntry($0.projects, $1) },
        .init(entityName: "ProjectSession") { try ndjsonEntry($0.projectSessions, $1) },
        .init(entityName: "ProjectRole") { try ndjsonEntry($0.projectRoles, $1) },

        // Optional arrays (v8+ extensions)
        .init(entityName: "WorkModel") { try ndjsonEntry($0.workModels, $1) },
        .init(entityName: "WorkCheckIn") { try ndjsonEntry($0.workCheckIns, $1) },
        .init(entityName: "WorkStep") { try ndjsonEntry($0.workSteps, $1) },
        .init(entityName: "WorkParticipantEntity") { try ndjsonEntry($0.workParticipants, $1) },
        .init(entityName: "PracticeSession") { try ndjsonEntry($0.practiceSessions, $1) },
        .init(entityName: "LessonAttachment") { try ndjsonEntry($0.lessonAttachments, $1) },
        .init(entityName: "LessonPresentation") { try ndjsonEntry($0.lessonPresentations, $1) },
        .init(entityName: "LessonRecallCheck") { try ndjsonEntry($0.recallChecks, $1) },
        .init(entityName: "SampleWork") { try ndjsonEntry($0.sampleWorks, $1) },
        .init(entityName: "SampleWorkStep") { try ndjsonEntry($0.sampleWorkSteps, $1) },
        .init(entityName: "NoteTemplate") { try ndjsonEntry($0.noteTemplates, $1) },
        .init(entityName: "MeetingTemplate") { try ndjsonEntry($0.meetingTemplates, $1) },
        .init(entityName: "Reminder") { try ndjsonEntry($0.reminders, $1) },
        .init(entityName: "CalendarEvent") { try ndjsonEntry($0.calendarEvents, $1) },
        .init(entityName: "Track") { try ndjsonEntry($0.tracks, $1) },
        .init(entityName: "TrackStep") { try ndjsonEntry($0.trackSteps, $1) },
        .init(entityName: "StudentTrackEnrollment") { try ndjsonEntry($0.studentTrackEnrollments, $1) },
        .init(entityName: "SequenceTrack") { try ndjsonEntry($0.sequenceTracks, $1) },
        .init(entityName: "Document") { try ndjsonEntry($0.documents, $1) },
        .init(entityName: "Supply") { try ndjsonEntry($0.supplies, $1) },
        .init(entityName: "Procedure") { try ndjsonEntry($0.procedures, $1) },
        .init(entityName: "Schedule") { try ndjsonEntry($0.schedules, $1) },
        .init(entityName: "ScheduleSlot") { try ndjsonEntry($0.scheduleSlots, $1) },
        .init(entityName: "Issue") { try ndjsonEntry($0.issues, $1) },
        .init(entityName: "IssueAction") { try ndjsonEntry($0.issueActions, $1) },
        .init(entityName: "DevelopmentSnapshot") { try ndjsonEntry($0.developmentSnapshots, $1) },
        .init(entityName: "TodoItem") { try ndjsonEntry($0.todoItems, $1) },
        .init(entityName: "TodoSubtask") { try ndjsonEntry($0.todoSubtasks, $1) },
        .init(entityName: "TodoTemplate") { try ndjsonEntry($0.todoTemplates, $1) },
        .init(entityName: "TodayAgendaOrder") { try ndjsonEntry($0.todayAgendaOrders, $1) },
        .init(entityName: "PlanningRecommendation") { try ndjsonEntry($0.planningRecommendations, $1) },
        .init(entityName: "Resource") { try ndjsonEntry($0.resources, $1) },
        .init(entityName: "NoteStudentLink") { try ndjsonEntry($0.noteStudentLinks, $1) },
        .init(entityName: "GoingOut") { try ndjsonEntry($0.goingOuts, $1) },
        .init(entityName: "GoingOutChecklistItem") { try ndjsonEntry($0.goingOutChecklistItems, $1) },
        .init(entityName: "ClassroomJob") { try ndjsonEntry($0.classroomJobs, $1) },
        .init(entityName: "JobAssignment") { try ndjsonEntry($0.jobAssignments, $1) },
        .init(entityName: "CalendarNote") { try ndjsonEntry($0.calendarNotes, $1) },
        .init(entityName: "ScheduledMeeting") { try ndjsonEntry($0.scheduledMeetings, $1) },
        .init(entityName: "ClassroomMembership") { try ndjsonEntry($0.classroomMemberships, $1) },
        .init(entityName: "MeetingWorkReview") { try ndjsonEntry($0.meetingWorkReviews, $1) },
        .init(entityName: "StudentFocusItem") { try ndjsonEntry($0.studentFocusItems, $1) },

        // Format v18+ extensions
        .init(entityName: "DayPad") { try ndjsonEntry($0.dayPads, $1) },
        .init(entityName: "YearPlanEntry") { try ndjsonEntry($0.yearPlanEntries, $1) },
        .init(entityName: "LessonSequenceSettings") { try ndjsonEntry($0.lessonSequenceSettings, $1) },
        .init(entityName: "Story") { try ndjsonEntry($0.stories, $1) },
        .init(entityName: "BookClubPacket") { try ndjsonEntry($0.bookClubPackets, $1) },
        .init(entityName: "BookClubSession") { try ndjsonEntry($0.bookClubSessions, $1) },
        .init(entityName: "BookClubMeeting") { try ndjsonEntry($0.bookClubMeetings, $1) }
    ]

    /// Every entity name this writer can serialize, in archive order. The
    /// coverage tests compare this against `BackupEntityRegistry`.
    public static var serializedEntityNames: [String] {
        entitySerializations.map(\.entityName)
    }

    /// An encode failure here aborts the whole export (wrapped in
    /// `WriterError.entityEncodingFailed`) — a backup that silently omits an
    /// entity type would verify clean and read back as data loss months later.
    static func serializeEntries(from payload: BackupPayload) throws -> [BackupEntityEntry] {
        let encoder = ndjsonEncoder()
        var entries: [BackupEntityEntry] = []
        entries.reserveCapacity(entitySerializations.count)

        for serialization in entitySerializations {
            do {
                guard let (ndjson, count) = try serialization.encode(payload, encoder) else { continue }
                entries.append(BackupEntityEntry(
                    entityName: serialization.entityName,
                    storeName: store(for: serialization.entityName),
                    count: count,
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

    /// Encodes a DTO array as NDJSON. Returns nil for nil/empty arrays so the
    /// archive only carries non-empty entries.
    private static func ndjsonEntry<T: Encodable>(
        _ dtos: [T]?,
        _ encoder: JSONEncoder
    ) throws -> (ndjson: Data, count: Int)? {
        guard let dtos, !dtos.isEmpty else { return nil }
        var buffer = Data()
        let newline = Data([0x0A])
        for dto in dtos {
            let line = try encoder.encode(dto)
            buffer.append(line)
            buffer.append(newline)
        }
        return (buffer, dtos.count)
    }

    // MARK: - Manifest

    private static func buildManifest(
        entries: [BackupEntityEntry],
        deviceName: String
    ) -> BackupArchiveManifest {
        var counts: [String: Int] = [:]
        var stores: [String: String] = [:]
        for entry in entries {
            counts[entry.entityName] = entry.count
            stores[entry.entityName] = entry.storeName
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
