import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Archives, restores and store comparisons for the restore suites.
@MainActor
enum BackupRestoreFixtures {
    typealias Fixtures = BackupStreamingFixtures

    /// The settings a test archive carries: none, so restoring one applies
    /// nothing to the process-wide defaults other suites read.
    static let noPreferences = PreferencesDTO(values: [:])

    /// A recorder that writes and restores `noPreferences`, optionally failing
    /// at a phase.
    static func recorder(
        onPhase: (@Sendable (String) -> Void)? = nil,
        failure: (@Sendable (String) -> (any Error)?)? = nil
    ) -> BackupPipelineRecorder {
        BackupPipelineRecorder(preferences: noPreferences, onPhase: onPhase, failure: failure)
    }

    // MARK: - Archives

    /// A backup of every type — notes, attendance and check-ins past one fetch
    /// batch — with no settings.
    static func makeBackup(bulk: Int = 1_000) async throws -> (store: Fixtures.Store, url: URL) {
        let store = try Fixtures.makeStore()
        try Fixtures.seedEveryType(in: store.context, bulk: bulk)
        let url = store.archiveURL("Source")
        try await writeBackup(of: store.context, to: url)
        return (store, url)
    }

    static func writeBackup(of context: NSManagedObjectContext, to url: URL) async throws {
        _ = try await BackupPipelineRecorder.$current.withValue(recorder()) {
            try await BackupWriter.write(viewContext: context, to: url)
        }
    }

    /// Writes `entries` as an encrypted archive with the app's key, in order.
    static func writeArchive(_ entries: [(path: String, data: Data)], to url: URL) throws {
        let key = try BackupEncryptionKeyStore.fetchOrCreateKey()
        try BackupArchive.write(to: url, encryptionKey: key) { appender in
            for entry in entries {
                try appender.append(path: entry.path, data: entry.data)
            }
        }
    }

    static func path(_ entityName: String) -> String {
        "\(BackupWriter.store(for: entityName))/\(entityName).ndjson"
    }

    // MARK: - Restores

    /// What a restore reported.
    struct Outcome {
        let summary: BackupOperationSummary
        let progress: [Fixtures.ProgressStep]
    }

    /// The restore as it was: every entry read, the whole archive decoded, then
    /// the old import.
    static func legacyRestore(
        _ url: URL,
        into context: NSManagedObjectContext,
        mode: BackupService.RestoreMode
    ) async throws -> Outcome {
        let log = Fixtures.ProgressLog()
        let archive = try await BackupImporter.legacyDecodeArchive(at: url)
        let summary = try await BackupImporter.legacyImportDecoded(
            archive, from: url, into: context, mode: mode, appRouter: AppRouter(),
            progress: { log.append($0, $1) }
        )
        return Outcome(summary: summary, progress: log.steps)
    }

    /// The app's restore.
    static func restore(
        _ url: URL,
        into context: NSManagedObjectContext,
        mode: BackupService.RestoreMode
    ) async throws -> Outcome {
        let log = Fixtures.ProgressLog()
        let summary = try await BackupImporter.restore(
            from: url, into: context, mode: mode, appRouter: AppRouter(),
            progress: { log.append($0, $1) }
        )
        return Outcome(summary: summary, progress: log.steps)
    }

    static func expectSameOutcome(_ new: Outcome, _ old: Outcome, _ situation: String) {
        #expect(new.progress == old.progress, "\(situation): progress")
        let (now, before) = (new.summary, old.summary)
        #expect(now.kind == before.kind, "\(situation): kind")
        #expect(now.fileName == before.fileName, "\(situation): file name")
        #expect(now.formatVersion == before.formatVersion, "\(situation): format version")
        #expect(now.encryptUsed == before.encryptUsed, "\(situation): encryption")
        #expect(now.createdAt == before.createdAt, "\(situation): created")
        #expect(now.entityCounts == before.entityCounts, "\(situation): counts")
        #expect(now.warnings == before.warnings, "\(situation): warnings")
    }

    // MARK: - Comparing restores

    /// The order the restore has always imported types in: parents first.
    static let restoreOrder = [
        "Student", "Lesson", "CommunityTopic", "LessonAssignment", "Note",
        "NonSchoolDay", "SchoolDayOverride", "StudentMeeting", "ProposedSolution", "CommunityAttachment",
        "AttendanceRecord", "WorkCompletionRecord", "Project", "ProjectRole", "ProjectSession",
        "WorkModel", "WorkCheckIn", "WorkStep", "WorkParticipantEntity", "PracticeSession",
        "LessonAttachment", "LessonPresentation", "LessonRecallCheck", "SampleWork", "SampleWorkStep",
        "NoteTemplate", "MeetingTemplate", "Reminder", "CalendarEvent",
        "Track", "TrackStep", "StudentTrackEnrollment", "SequenceTrack",
        "Document", "Supply", "Procedure", "Schedule", "ScheduleSlot", "Issue", "IssueAction",
        "DevelopmentSnapshot", "TodoItem", "TodoSubtask", "TodoTemplate", "TodayAgendaOrder",
        "PlanningRecommendation", "Resource", "NoteStudentLink",
        "GoingOut", "GoingOutChecklistItem", "ClassroomJob", "JobAssignment", "CalendarNote", "ScheduledMeeting",
        "ClassroomMembership", "MeetingWorkReview", "StudentFocusItem",
        "DayPad", "YearPlanEntry", "LessonSequenceSettings", "Story",
        "BookClubPacket", "BookClubSession", "BookClubMeeting", "Guardian", "ParentCommunication",
        "AlbumBookmark", "AlbumPageNote", "AlbumRecentVisit", "AlbumReadingPosition", "AlbumHighlight",
        "AlbumPageInk", "OrderItem", "AttendanceDayLock"
    ]

    /// Restores `url` into two fresh stores prepared alike, the old way and
    /// the new, and expects the same records, summary and progress. Returns
    /// the new way's stack (keep it alive while reading its context).
    static func expectSameRestore(
        of url: URL,
        mode: BackupService.RestoreMode,
        preparing prepare: (NSManagedObjectContext) async throws -> Void = { _ in },
        _ situation: String
    ) async throws -> CoreDataStack {
        let old = try CoreDataTestHelpers.makeInMemoryStack()
        let new = try CoreDataTestHelpers.makeInMemoryStack()
        try await prepare(old.viewContext)
        try await prepare(new.viewContext)
        try expectSameStore(new.viewContext, old.viewContext, "\(situation), before")

        let oldOutcome = try await legacyRestore(url, into: old.viewContext, mode: mode)
        let newOutcome = try await restore(url, into: new.viewContext, mode: mode)
        expectSameOutcome(newOutcome, oldOutcome, situation)
        try expectSameStore(new.viewContext, old.viewContext, situation)
        try expectSameBackup(new.viewContext, old.viewContext, situation)
        #expect(!new.viewContext.hasChanges, "\(situation): saved")
        return new
    }

    /// Some of the backup's records already in the store, holding only their
    /// ids, and notes the backup lacks.
    static func seedOverlap(of payload: BackupPayload, extra: [UUID], into context: NSManagedObjectContext) {
        let present: [(entity: String, ids: [UUID])] = [
            ("Student", payload.students.map(\.id)),
            ("Lesson", payload.lessons.map(\.id)),
            ("Note", Array(payload.notes.map(\.id).prefix(400))),
            ("AttendanceRecord", Array(payload.attendance.map(\.id).suffix(250))),
            ("LessonAssignment", Array(payload.lessonAssignments.map(\.id).prefix(1))),
            ("WorkModel", payload.workModels?.map(\.id) ?? []),
            ("Track", payload.tracks?.map(\.id) ?? [])
        ]
        for (entity, ids) in present {
            for id in ids {
                NSEntityDescription.insertNewObject(forEntityName: entity, into: context).setValue(id, forKey: "id")
            }
        }
        for (number, id) in extra.enumerated() {
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
            note.setValue(id, forKey: "id")
            note.setValue("Kept \(number)", forKey: "body")
            note.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "createdAt")
        }
    }

    /// `source`'s entries with a Student row that does not decode, Lesson
    /// twice (the second doubled), Note twice (the second unreadable),
    /// WorkModel twice (the first unreadable), and two entities this version
    /// does not know.
    static func brokenEntries(from source: Fixtures.ArchiveContents) throws -> [(path: String, data: Data)] {
        var entries: [(path: String, data: Data)] = []
        for path in source.paths {
            let body = try #require(source.bodies[path])
            switch path {
            case Self.path("Student"):
                entries.append((path, body + Data("{\"id\":5}\n".utf8)))
                entries.append(("private/Mystery.ndjson", Data("{\"id\":\"x\"}\n".utf8)))
            case Self.path("Lesson"):
                entries += [(path, body), (path, body + body)]
            case Self.path("Note"):
                entries += [(path, body), (path, Data("not json\n".utf8))]
            case Self.path("WorkModel"):
                entries += [(path, Data("not json\n".utf8)), (path, body)]
            default:
                entries.append((path, body))
            }
        }
        entries.append(("shared/Riddle.ndjson", Data("{}\n".utf8)))
        return entries
    }
}
