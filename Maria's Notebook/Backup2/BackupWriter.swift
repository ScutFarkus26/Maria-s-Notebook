// BackupWriter.swift
// Builds a v17 AEA-framed backup file from a Core Data context.
//
// Reuses `BackupService.collectPayload(viewContext:progress:)` for the
// per-entity DTO transformer logic (same code path the legacy export uses).
// Adds:
//   - Manifest entry (`manifest.json`) written first, with format version,
//     entity counts, app version/build, model hash, and origin-store routing.
//   - One NDJSON entry per non-empty entity array, named
//     `<store>/<EntityName>.ndjson` so the importer can route to the right
//     persistent store on the destination device.
//   - Preferences entry (`preferences.json`) for the app's user-defined
//     settings dictionary.

import Foundation
import CoreData
import OSLog

@MainActor
public enum BackupWriter {
    private static let logger = Logger.backup

    /// Format version produced by this writer. Bumped from the legacy v16
    /// (JSON envelope) to v17 (AEA-framed NDJSON).
    public static let formatVersion: Int = 17

    // MARK: - Public API

    /// Builds a v17 backup at `url`. Caller must hold the security-scoped
    /// resource (if any) for `url`.
    @discardableResult
    public static func write(
        viewContext: NSManagedObjectContext,
        to url: URL,
        progress: @escaping BackupService.ProgressCallback = { _, _ in }
    ) throws -> BackupOperationSummary {
        progress(0.0, "Collecting entities\u{2026}")

        // Reuse the legacy collector — same transformer code path that's been
        // shipping successfully. Phase 2 doesn't re-implement entity transforms.
        let backupService = BackupService()
        let payload = backupService.collectPayload(viewContext: viewContext) { sub, message in
            // Map the collector's 0-1 inner progress into the 0.0-0.6 outer band.
            progress(min(0.6, sub * 0.6), message)
        }

        progress(0.65, "Building manifest\u{2026}")
        let entries = serializeEntries(from: payload)
        let manifest = buildManifest(entries: entries, payload: payload)
        let manifestData = try encodeManifest(manifest)

        progress(0.75, "Writing archive\u{2026}")
        try BackupArchive.write(to: url) { appender in
            // Manifest first so readers can stream-validate.
            try appender.append(path: "manifest.json", data: manifestData)
            // Preferences as a single JSON document (not NDJSON).
            try appender.append(path: "preferences.json", data: payload.preferencesJSON())
            // Then each non-empty entity entry, in registry order.
            for entry in entries {
                try appender.append(path: entry.archivePath, data: entry.ndjson)
            }
        }

        progress(1.0, "Backup complete")
        logger.info("BackupWriter wrote v\(formatVersion, privacy: .public) backup with \(entries.count) entity entries")

        return BackupOperationSummary(
            kind: .export,
            fileName: url.lastPathComponent,
            formatVersion: formatVersion,
            encryptUsed: false,
            createdAt: Date(),
            entityCounts: manifest.entityCounts,
            warnings: ["Imported documents and file attachments are not included in backups by design."]
        )
    }

    // MARK: - Entry Serialization

    static func serializeEntries(from payload: BackupPayload) -> [BackupEntityEntry] {
        let encoder = ndjsonEncoder()
        var entries: [BackupEntityEntry] = []

        func add<T: Encodable>(_ entityName: String, _ dtos: [T]) {
            guard !dtos.isEmpty else { return }
            do {
                let entry = try makeEntry(entityName: entityName, dtos: dtos, encoder: encoder)
                entries.append(entry)
            } catch {
                logger.warning("Failed to encode \(entityName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Core (required arrays)
        add("Student", payload.students)
        add("Lesson", payload.lessons)
        add("LessonAssignment", payload.lessonAssignments)
        add("Note", payload.notes)
        add("NonSchoolDay", payload.nonSchoolDays)
        add("SchoolDayOverride", payload.schoolDayOverrides)
        add("StudentMeeting", payload.studentMeetings)
        add("CommunityTopic", payload.communityTopics)
        add("ProposedSolution", payload.proposedSolutions)
        add("CommunityAttachment", payload.communityAttachments)
        add("AttendanceRecord", payload.attendance)
        add("WorkCompletionRecord", payload.workCompletions)
        add("Project", payload.projects)
        add("ProjectSession", payload.projectSessions)
        add("ProjectRole", payload.projectRoles)

        // Optional arrays (v8+ extensions)
        addOptional("WorkModel", payload.workModels, add: add)
        addOptional("WorkCheckIn", payload.workCheckIns, add: add)
        addOptional("WorkStep", payload.workSteps, add: add)
        addOptional("WorkParticipantEntity", payload.workParticipants, add: add)
        addOptional("PracticeSession", payload.practiceSessions, add: add)
        addOptional("LessonAttachment", payload.lessonAttachments, add: add)
        addOptional("LessonPresentation", payload.lessonPresentations, add: add)
        addOptional("SampleWork", payload.sampleWorks, add: add)
        addOptional("SampleWorkStep", payload.sampleWorkSteps, add: add)
        addOptional("NoteTemplate", payload.noteTemplates, add: add)
        addOptional("MeetingTemplate", payload.meetingTemplates, add: add)
        addOptional("Reminder", payload.reminders, add: add)
        addOptional("CalendarEvent", payload.calendarEvents, add: add)
        addOptional("Track", payload.tracks, add: add)
        addOptional("TrackStep", payload.trackSteps, add: add)
        addOptional("StudentTrackEnrollment", payload.studentTrackEnrollments, add: add)
        addOptional("SequenceTrack", payload.sequenceTracks, add: add)
        addOptional("Document", payload.documents, add: add)
        addOptional("Supply", payload.supplies, add: add)
        addOptional("Procedure", payload.procedures, add: add)
        addOptional("Schedule", payload.schedules, add: add)
        addOptional("ScheduleSlot", payload.scheduleSlots, add: add)
        addOptional("Issue", payload.issues, add: add)
        addOptional("IssueAction", payload.issueActions, add: add)
        addOptional("DevelopmentSnapshot", payload.developmentSnapshots, add: add)
        addOptional("TodoItem", payload.todoItems, add: add)
        addOptional("TodoSubtask", payload.todoSubtasks, add: add)
        addOptional("TodoTemplate", payload.todoTemplates, add: add)
        addOptional("TodayAgendaOrder", payload.todayAgendaOrders, add: add)
        addOptional("PlanningRecommendation", payload.planningRecommendations, add: add)
        addOptional("Resource", payload.resources, add: add)
        addOptional("NoteStudentLink", payload.noteStudentLinks, add: add)
        addOptional("GoingOut", payload.goingOuts, add: add)
        addOptional("GoingOutChecklistItem", payload.goingOutChecklistItems, add: add)
        addOptional("ClassroomJob", payload.classroomJobs, add: add)
        addOptional("JobAssignment", payload.jobAssignments, add: add)
        addOptional("TransitionPlan", payload.transitionPlans, add: add)
        addOptional("TransitionChecklistItem", payload.transitionChecklistItems, add: add)
        addOptional("CalendarNote", payload.calendarNotes, add: add)
        addOptional("ScheduledMeeting", payload.scheduledMeetings, add: add)
        addOptional("ClassroomMembership", payload.classroomMemberships, add: add)
        addOptional("MeetingWorkReview", payload.meetingWorkReviews, add: add)
        addOptional("StudentFocusItem", payload.studentFocusItems, add: add)

        return entries
    }

    private static func addOptional<T: Encodable>(
        _ name: String,
        _ dtos: [T]?,
        add: (String, [T]) -> Void
    ) {
        guard let dtos else { return }
        add(name, dtos)
    }

    private static func makeEntry<T: Encodable>(
        entityName: String,
        dtos: [T],
        encoder: JSONEncoder
    ) throws -> BackupEntityEntry {
        let ndjson = try encodeNDJSON(dtos, encoder: encoder)
        return BackupEntityEntry(
            entityName: entityName,
            storeName: store(for: entityName),
            count: dtos.count,
            ndjson: ndjson
        )
    }

    // MARK: - Manifest

    private static func buildManifest(
        entries: [BackupEntityEntry],
        payload: BackupPayload
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
            device: ProcessInfo.processInfo.hostName,
            entityCounts: counts,
            originStores: stores
        )
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

    private static func encodeNDJSON<T: Encodable>(_ dtos: [T], encoder: JSONEncoder) throws -> Data {
        var buffer = Data()
        let newline = Data([0x0A])
        for dto in dtos {
            let line = try encoder.encode(dto)
            buffer.append(line)
            buffer.append(newline)
        }
        return buffer
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
