import Foundation
import CoreData
import OSLog

/// Analyzes backup payloads to generate preview statistics for restore operations.
///
/// This extracts the analysis logic from BackupService.previewImport() for better
/// testability and separation of concerns. It reads a `BackupPreviewDigest` —
/// row counts, IDs and change dates — which is all the analysis needs from a
/// backup. Both modes go over every backed-up type (`BackupEntityTable`), as
/// the restore does: until 2026-11-02 a Merge's preview counted 15 hand-picked
/// types, and showed "Nothing would change" for a backup of thousands of work
/// records (bug hunt 2026-11-02, #22).
enum BackupPreviewAnalyzer {
    private static let logger = Logger.backup

    /// Result of analyzing a backup payload against the current database state.
    struct AnalysisResult {
        var inserts: [String: Int] = [:]
        /// Records already here that the restore brings to the backup's version.
        var skips: [String: Int] = [:]
        var deletes: [String: Int] = [:]
        /// Records already here that the restore leaves as they are, changed
        /// here since the backup (a Merge's newer wins, `BackupMergeRule`;
        /// bug hunt 2026-11-02, #1). The preview shows them as "kept".
        var kept: [String: Int] = [:]
        var warnings: [String] = []

        var totalInserts: Int { inserts.values.reduce(0, +) }
        var totalDeletes: Int { deletes.values.reduce(0, +) }
    }

    /// Analyzes a backup's digest to determine what changes would occur during restore.
    ///
    /// - Parameters:
    ///   - digest: The backup's row counts, IDs and change dates
    ///   - viewContext: The model context for checking existing entities
    ///   - mode: The restore mode (replace or merge)
    ///   - formatVersion: The backup's format: replace leaves the types it predates
    ///   - entityExists: Closure to check if an entity exists by type and ID
    /// - Returns: Analysis result with insert/skip/delete counts per entity type
    static func analyze(
        digest: BackupPreviewDigest,
        viewContext: NSManagedObjectContext,
        mode: BackupService.RestoreMode,
        formatVersion: Int,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool
    ) -> AnalysisResult {
        var result = AnalysisResult()
        let store = StoredRecords(context: viewContext, exists: entityExists)
        if mode == .replace {
            analyzeReplaceMode(
                digest: digest, viewContext: viewContext, formatVersion: formatVersion, store: store, into: &result
            )
        } else {
            analyzeMergeMode(digest: digest, viewContext: viewContext, store: store, into: &result)
        }
        return result
    }

    // MARK: - Replace Mode Analysis

    private static func analyzeReplaceMode(
        digest: BackupPreviewDigest,
        viewContext: NSManagedObjectContext,
        formatVersion: Int,
        store: StoredRecords,
        into result: inout AnalysisResult
    ) {
        // Replace-mode restore deletes every type in BackupEntityTable, but for
        // those BackupService+Helpers.deleteAll leaves, and re-inserts the
        // payload, so the preview enumerates that same table with the same
        // exceptions. A hand-picked subset here once under-reported the
        // destructive-restore consent numbers by ~35 types.
        let model = viewContext.persistentStoreCoordinator?.managedObjectModel
        let insertCounts = insertCountsByDisplayName(digest)

        for entity in BackupEntityTable.entities {
            // Types the restore leaves as they are (this device's pin, the
            // mirrored Apple Calendar events, any the backup is too old
            // to hold, and any whose entry didn't decode) are neither cleared
            // nor restored, so the consent numbers don't count them.
            guard let key = previewKey(for: entity), entity.isCarried(by: formatVersion),
                  !digest.skippedEntityNames.contains(entity.name) else { continue }
            let type = entity.managedType()
            if BackupEntityRegistry.mergedOnReplaceEntityNames.contains(key) {
                // The names people set are updated as a Merge updates them, never cleared.
                countMerge(digest.stamps(entity.name), of: type, as: key, store, into: &result)
            } else if BackupEntityRegistry.updatedInPlaceOnReplaceEntityNames.contains(key) {
                // The classroom share's records are updated where they are;
                // only those the backup lacks go (bug hunt 2026-11-02, #2).
                let inBackup = Set(digest.ids(entity.name))
                let here = storedIDs(of: type, model: model, in: viewContext)
                let hereIDs = Set(here.compactMap { $0 })
                result.inserts[key] = inBackup.subtracting(hereIDs).count
                result.skips[key] = inBackup.intersection(hereIDs).count
                result.deletes[key] = here.filter { $0.map { !inBackup.contains($0) } ?? true }.count
            } else {
                result.inserts[key] = insertCounts[key] ?? 0
                result.skips[key] = 0
                result.deletes[key] = existingCount(of: type, model: model, in: viewContext)
            }
        }

        // Deprecated payload sections with no live entity behind them: nothing
        // gets deleted, but old backups may still carry records.
        result.inserts["ProjectAssignmentTemplate"] = digest.projectAssignmentTemplateCount
        result.inserts["ProjectTemplateWeek"] = digest.projectTemplateWeekCount
        result.inserts["ProjectWeekRoleAssignment"] = digest.projectWeekRoleAssignmentCount
        for key in ["ProjectAssignmentTemplate", "ProjectTemplateWeek", "ProjectWeekRoleAssignment"] {
            result.skips[key] = 0
            result.deletes[key] = 0
        }
    }

    /// The key `entity`'s counts go under ("CDCommunityTopicEntity" →
    /// "CommunityTopic"); nil for a type the restore never writes (not yet
    /// backed up, or left as it is on every restore).
    private static func previewKey(for entity: BackupEntity) -> String? {
        let registryName = BackupEntityRegistry.entityName(for: entity.managedType())
        guard !BackupEntityRegistry.notYetBackedUpEntityNames.contains(registryName) else { return nil }
        let key = displayName(forEntityTypeName: registryName)
        guard !BackupEntityRegistry.keptOnRestoreEntityNames.contains(key) else { return nil }
        return key
    }

    /// "CDCommunityTopicEntity" → "CommunityTopic"
    private static func displayName(forEntityTypeName name: String) -> String {
        var result = name
        if result.hasPrefix("CD") { result.removeFirst(2) }
        if result.hasSuffix("Entity") { result.removeLast("Entity".count) }
        return result
    }

    /// The model entity behind `type`; nil for a legacy stub the model lacks.
    private static func modelEntityName(of type: NSManagedObject.Type, model: NSManagedObjectModel?) -> String? {
        let className = NSStringFromClass(type)
        return model?.entitiesByName.first(where: { $0.value.managedObjectClassName == className })?.key
    }

    private static func existingCount(
        of type: NSManagedObject.Type,
        model: NSManagedObjectModel?,
        in viewContext: NSManagedObjectContext
    ) -> Int {
        // Skip types whose entity doesn't exist in the Core Data model (legacy stubs)
        guard let entityName = modelEntityName(of: type, model: model) else { return 0 }
        // The private store only: a replace restore clears only that one
        // (`BackupRestoreScope`), so a classroom someone else shared with this
        // notebook isn't counted as removed.
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        BackupRestoreScope.limitToNotebook(request, in: viewContext)
        do {
            return try viewContext.count(for: request)
        } catch {
            logger.warning("Failed to count \(entityName): \(error)")
            return 0
        }
    }

    /// Every one of the notebook's records of `type`, by `id` (nil for one
    /// without), as the in-place Replace sees them.
    private static func storedIDs(
        of type: NSManagedObject.Type,
        model: NSManagedObjectModel?,
        in viewContext: NSManagedObjectContext
    ) -> [UUID?] {
        guard let entityName = modelEntityName(of: type, model: model) else { return [] }
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        BackupRestoreScope.limitToNotebook(request, in: viewContext)
        do {
            return try viewContext.fetch(request).map { $0["id"] as? UUID }
        } catch {
            logger.warning("Failed to read \(entityName) ids: \(error)")
            return []
        }
    }

    /// Insert counts from the digest, keyed by the display names derived from
    /// BackupEntityRegistry (see `displayName(forEntityTypeName:)`). The album
    /// annotation types have never been listed here, so replace mode shows no
    /// inserts for them.
    private static func insertCountsByDisplayName(_ digest: BackupPreviewDigest) -> [String: Int] {
        var counts: [String: Int] = [:]
        for key in insertCountKeys {
            counts[key] = digest.count(key == "WorkParticipant" ? "WorkParticipantEntity" : key)
        }
        return counts
    }

    /// Display names reported as replace-mode inserts. Each is also the archive
    /// entity name, except "WorkParticipant" ("WorkParticipantEntity").
    private static let insertCountKeys: [String] = [
        "Student", "Lesson", "LessonAttachment", "LessonAssignment", "LessonPresentation",
        "LessonRecallCheck", "Note", "NoteStudentLink", "NonSchoolDay", "SchoolDayOverride",
        "StudentMeeting", "MeetingTemplate", "CommunityTopic", "ProposedSolution", "CommunityAttachment",
        "AttendanceRecord", "WorkModel", "WorkCompletionRecord", "WorkCheckIn", "WorkParticipant",
        "WorkStep", "SampleWork", "SampleWorkStep", "Project",
        "ProjectSession", "ProjectRole", "Issue", "IssueAction", "Track",
        "TrackStep", "StudentTrackEnrollment", "SequenceTrack", "NoteTemplate",
        "CalendarEvent", "Document", "Supply", "Procedure", "Schedule",
        "ScheduleSlot", "DevelopmentSnapshot", "TodoItem",
        "TodayAgendaOrder", "DayPad", "PlanningRecommendation", "Resource", "GoingOut",
        "GoingOutChecklistItem", "CalendarNote", "ScheduledMeeting",
        "ClassroomMembership", "MeetingWorkReview", "StudentFocusItem", "YearPlanEntry", "LessonSequenceSettings",
        "Story", "BookClubPacket", "BookClubSession", "BookClubMeeting", "Guardian",
        "ParentCommunication", "OrderItem", "AttendanceDayLock", "SupplyTransaction",
        "AttendanceEmailSend", "AttendanceEmailSettings", "ClassroomPerson",
        "TimetableLane", "TimetableBlock", "TimetableChange", "TimetableBooking"
    ]

    // MARK: - Merge Mode Analysis

    private static func analyzeMergeMode(
        digest: BackupPreviewDigest,
        viewContext: NSManagedObjectContext,
        store: StoredRecords,
        into result: inout AnalysisResult
    ) {
        for entity in BackupEntityTable.entities {
            guard let key = previewKey(for: entity) else { continue }
            if entity.name == "LessonAssignment" {
                analyzeLessonAssignmentMerge(digest: digest, viewContext: viewContext, store: store, into: &result)
            } else {
                countMerge(digest.stamps(entity.name), of: entity.managedType(), as: key, store, into: &result)
            }
        }
        for key in ["ProjectAssignmentTemplate", "ProjectTemplateWeek", "ProjectWeekRoleAssignment"] {
            result.inserts[key] = 0
            result.skips[key] = 0
            result.deletes[key] = 0
        }
    }

    /// Sorts `rows` as a Merge restores them: a new record is added, one
    /// changed here since the backup (or a to-do done since) is kept, and
    /// any other already here takes the backup's version (an older record,
    /// or a type or row without a change date): `BackupMergeRule`.
    private static func countMerge(
        _ rows: [BackupPreviewDigest.RowStamp],
        of type: NSManagedObject.Type,
        as key: String,
        _ store: StoredRecords,
        into result: inout AnalysisResult
    ) {
        var counts = MergeCounts(keepsDatedOverDateless: BackupEntityRegistry.mergedOnReplaceEntityNames.contains(key))
        for row in rows {
            counts.add(row, of: type, store)
        }
        result.inserts[key] = counts.ins
        result.skips[key] = counts.sk
        result.deletes[key] = 0
        if counts.kept > 0 { result.kept[key] = counts.kept }
    }

    private struct MergeCounts {
        /// The names people set: one here with a date stands against a
        /// backup row with none (`BackupRestoreRun.keepingNewer`).
        var keepsDatedOverDateless = false
        var ins = 0
        var sk = 0
        var kept = 0
        var missingLesson = 0

        mutating func add(_ row: BackupPreviewDigest.RowStamp, of type: NSManagedObject.Type, _ store: StoredRecords) {
            if !store.exists(type, row.id) {
                ins += 1
            } else if let stored = store.stamp(of: type, id: row.id),
                      BackupMergeRule.keepsStored(
                          stored, rowChangedAt: row.modifiedAt, rowCompletedAt: row.completedAt,
                          keepsDatedOverDateless: keepsDatedOverDateless
                      ) {
                kept += 1
            } else {
                sk += 1
            }
        }
    }

    private static func analyzeLessonAssignmentMerge(
        digest: BackupPreviewDigest,
        viewContext: NSManagedObjectContext,
        store: StoredRecords,
        into result: inout AnalysisResult
    ) {
        // Build lesson lookup sets for the missing-lesson warning.
        let lessonsInStore: Set<UUID>
        do {
            let request = CDFetchRequest(CDLesson.self)
            BackupRestoreScope.limitToNotebook(request, in: viewContext)
            lessonsInStore = Set(try viewContext.fetch(request).compactMap(\.id))
        } catch {
            logger.warning("Failed to fetch lessons: \(error)")
            lessonsInStore = Set()
        }
        let lessonsInPayload = Set(digest.ids("Lesson"))

        var counts = MergeCounts()
        for assignment in digest.lessonAssignments {
            // The importer drops assignments whose lessonID isn't a valid
            // UUID: nothing changes for them, so they aren't counted.
            guard let lessonUUID = UUID(uuidString: assignment.lessonID) else { continue }
            let isNew = !store.exists(CDLessonAssignment.self, assignment.id)
            counts.add(.init(id: assignment.id, modifiedAt: assignment.modifiedAt), of: CDLessonAssignment.self, store)
            // The importer inserts assignments even when the lesson is missing
            // from both the payload and the library — they restore unlinked,
            // they are NOT skipped (BackupEntityImporter+Lessons).
            if isNew && !lessonsInStore.contains(lessonUUID) && !lessonsInPayload.contains(lessonUUID) {
                counts.missingLesson += 1
            }
        }
        result.inserts["LessonAssignment"] = counts.ins
        result.skips["LessonAssignment"] = counts.sk
        result.deletes["LessonAssignment"] = 0
        if counts.kept > 0 { result.kept["LessonAssignment"] = counts.kept }
        if counts.missingLesson > 0 {
            result.warnings.append(
                "\(counts.missingLesson) lesson assignments reference lessons missing "
                + "from both this backup and the library; they will be restored but "
                + "stay unlinked until their lesson exists."
            )
        }
    }
}

/// What the analysis asks of the notebook: whether a record is here (the
/// caller's lookup), and the dates a Merge weighs by `id` (`BackupMergeRule`),
/// one narrow fetch per type the first time the analysis asks (types with
/// such a date only). Where synced copies share an `id`, the latest dates
/// stand for them all.
private final class StoredRecords {
    let exists: (NSManagedObject.Type, UUID) -> Bool
    private let context: NSManagedObjectContext
    private var stamps: [ObjectIdentifier: [UUID: BackupMergeRule.Stored]] = [:]

    init(context: NSManagedObjectContext, exists: @escaping (NSManagedObject.Type, UUID) -> Bool) {
        self.context = context
        self.exists = exists
    }

    func stamp(of type: NSManagedObject.Type, id: UUID) -> BackupMergeRule.Stored? {
        let key = ObjectIdentifier(type)
        if stamps[key] == nil { stamps[key] = fetch(type) }
        return stamps[key]?[id]
    }

    private func fetch(_ type: NSManagedObject.Type) -> [UUID: BackupMergeRule.Stored] {
        guard let entityName = BackupFetchHelper.entityName(for: type, in: context),
              let entity = context.persistentStoreCoordinator?.managedObjectModel.entitiesByName[entityName]
        else { return [:] }
        let dates = BackupMergeRule.Columns(entity)
        guard !dates.keys.isEmpty else { return [:] }
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"] + dates.keys
        BackupRestoreScope.limitToNotebook(request, in: context)
        var byID: [UUID: BackupMergeRule.Stored] = [:]
        for row in (try? context.fetch(request)) ?? [] {
            guard let id = row["id"] as? UUID, let stamp = dates.stored(from: row) else { continue }
            byID[id] = byID[id].map { $0.latest(with: stamp) } ?? stamp
        }
        return byID
    }
}
