import Foundation
import CoreData
import CloudKit
import os

// MARK: - Scope

/// Which entities a deduplication pass reads.
///
/// The launch pass sweeps everything. The post-import pass only needs the
/// entities the import inserted — a duplicate is two rows for one record, and
/// only an insert can add a row — and the history processor already knows
/// which those were. An entity outside the scope is not fetched at all, not
/// even its `id` column.
nonisolated struct DeduplicationScope: Sendable, Equatable {
    /// Core Data entity names, or `nil` for every entity.
    let entityNames: Set<String>?

    static let everything = DeduplicationScope(entityNames: nil)

    init(insertedEntities: Set<String>) {
        self.entityNames = insertedEntities
    }

    private init(entityNames: Set<String>?) {
        self.entityNames = entityNames
    }

    func includes(_ entityName: String) -> Bool {
        entityNames?.contains(entityName) ?? true
    }

    /// True when no entity is in scope, so a pass has nothing to read.
    var isEmpty: Bool {
        entityNames?.isEmpty == true
    }

    func includes<T: NSManagedObject>(_ type: T.Type) -> Bool {
        guard let entityNames else { return true }
        guard let name = CDFetchRequest(type).entityName else { return false }
        return entityNames.contains(name)
    }
}

// MARK: - Deduplication

nonisolated extension DataCleanupService {

    // MARK: - Generic Deduplication

    /// Deterministic cross-device survivor ordering for duplicates sharing one logical id.
    ///
    /// This pass runs independently on every synced device, so the survivor must be
    /// chosen from data every peer sees identically — otherwise two devices can keep
    /// opposite copies and each delete the other's, and both deletes sync (Apple's
    /// dedup guidance: pick the winner by a globally unique key so "all peers
    /// eventually reserve the same" record). Ordering:
    /// 1. Earliest `createdAt`, matching the draft-assignment dedup precedent above.
    /// 2. Lowest CloudKit record name — the same for a given record on every device.
    ///    A synced record outranks a local-only copy.
    /// 3. Object URI, reached only when neither record has been exported yet — such
    ///    copies exist on this device alone, so a local ordering cannot diverge.
    private static func precedesAsCanonical(
        _ lhs: NSManagedObject,
        _ rhs: NSManagedObject,
        container: NSPersistentCloudKitContainer?
    ) -> Bool {
        if lhs.entity.attributesByName["createdAt"] != nil {
            let lhsDate = lhs.value(forKey: "createdAt") as? Date ?? .distantFuture
            let rhsDate = rhs.value(forKey: "createdAt") as? Date ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
        }

        let lhsName = container?.recordID(for: lhs.objectID)?.recordName
        let rhsName = container?.recordID(for: rhs.objectID)?.recordName
        switch (lhsName, rhsName) {
        case let (.some(lhsRecord), .some(rhsRecord)) where lhsRecord != rhsRecord:
            return lhsRecord < rhsRecord
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        return lhs.objectID.uriRepresentation().absoluteString
            < rhs.objectID.uriRepresentation().absoluteString
    }

    /// Generic deduplication for any NSManagedObject with an id property.
    /// Keeps a deterministically chosen canonical instance and deletes duplicates,
    /// so every synced device converges on the same survivor.
    /// Returns the number of duplicates removed.
    @discardableResult
    static func deduplicate<T: NSManagedObject>(
        _ type: T.Type,
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything,
        merge: ((T, T) -> Void)? = nil
    ) -> Int {
        guard scope.includes(T.self) else { return 0 }

        // Cheap pre-check: read only the `id` column to learn whether this table
        // has duplicates at all. The answer is almost always "no", and finding
        // that out shouldn't fault every row of every entity into the context —
        // on the view context those objects then stay registered for the session.
        // `nil` means the pre-check couldn't be trusted, so fall back to the
        // original full-table pass.
        let duplicateIDs = duplicatedIDs(of: T.self, using: context)
        if let duplicateIDs, duplicateIDs.isEmpty { return 0 }

        let fetch = CDFetchRequest(T.self)
        if let duplicateIDs {
            // Only the colliding rows need to be materialized.
            fetch.predicate = NSPredicate(format: "id IN %@", Array(duplicateIDs))
        }
        let all: [T]
        do {
            all = try context.fetch(fetch)
        } catch {
            logger.warning("Failed to fetch \(type, privacy: .public): \(error.localizedDescription)")
            return 0
        }

        // Group by ID
        var byID: [UUID: [T]] = [:]
        for item in all {
            let itemID = item.value(forKey: "id") as? UUID ?? UUID()
            byID[itemID, default: []].append(item)
        }

        var deletedCount = 0

        for (_, items) in byID where items.count > 1 {
            let ordered = items.sorted { precedesAsCanonical($0, $1, container: container) }
            guard let canonical = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                merge?(canonical, duplicate)
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            context.safeSave()
        }

        return deletedCount
    }

    /// IDs that appear on more than one row of `type`, found by reading just the
    /// `id` column instead of materializing objects.
    ///
    /// Returns `nil` when the answer can't be trusted — a context with unsaved
    /// changes (dictionary-result fetches don't see pending inserts) or a failed
    /// fetch — in which case the caller should do the original full pass.
    private static func duplicatedIDs<T: NSManagedObject>(
        of type: T.Type,
        using context: NSManagedObjectContext
    ) -> Set<UUID>? {
        guard !context.hasChanges else { return nil }
        guard let entityName = CDFetchRequest(T.self).entityName else { return nil }

        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        // Rows with no id are never merged with each other — the object pass
        // hands each one a fresh UUID — so they can't contribute a duplicate.
        request.predicate = NSPredicate(format: "id != nil")

        let rows: [NSDictionary]
        do {
            rows = try context.fetch(request)
        } catch {
            return nil
        }

        var seen = Set<UUID>(minimumCapacity: rows.count)
        var duplicates = Set<UUID>()
        for row in rows {
            guard let id = row["id"] as? UUID else { continue }
            if !seen.insert(id).inserted { duplicates.insert(id) }
        }
        return duplicates
    }

    // MARK: - NSSet Merge Helper

    /// Merges NSSet-based to-many relationships from source into destination.
    /// Re-parents each child by calling the setter, and adds to canonical's set.
    static func mergeNSSetRelationship<T: NSManagedObject>(
        from source: NSSet?,
        addTo canonical: NSManagedObject,
        relationshipKey: String,
        existingIDs: inout Set<UUID>,
        setter: (T) -> Void
    ) {
        guard let sourceSet = source as? Set<T>, !sourceSet.isEmpty else { return }
        let mutableSet = canonical.mutableSetValue(forKey: relationshipKey)
        for item in sourceSet {
            let itemID = item.value(forKey: "id") as? UUID ?? UUID()
            if existingIDs.insert(itemID).inserted {
                setter(item)
                mutableSet.add(item)
            }
        }
    }

    // MARK: - Child-Preserving Merges for Cascade-Owning Entities
    //
    // These entities own Note (and MeetingWorkReview) children through Cascade
    // delete rules. The generic id-based `deduplicate(_:)` keeps the first row
    // and deletes the rest; without re-parenting first, Core Data cascade-
    // deletes the duplicate's children — silently destroying an observation
    // note that happened to attach to a non-canonical CloudKit duplicate. Each
    // merge re-points the duplicate's children onto the survivor before it is
    // deleted, mirroring how `mergeWorkModel`/`mergeNote` already protect their
    // children.
    //
    // The merges themselves live beside the entity family they belong to, in
    // the +Deduplicate<Family> files.

    // MARK: - Deduplicate All Models

    /// Deduplicates all model types in the database.
    ///
    /// Pass the owning `NSPersistentCloudKitContainer` whenever it is available:
    /// it lets survivor selection fall back to the CloudKit record name so every
    /// synced device converges on the same canonical record.
    @discardableResult
    static func deduplicateAllModels(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> [String: Int] {
        // Every step is gated on `scope` inside `deduplicate`; the two name-based
        // merges are gated on the entity they read.
        var results = curriculumDuplicates(in: context, container: container, scope: scope)
        results.merge(recordDuplicates(in: context, container: container, scope: scope)) { $1 }
        // Supplies, their history, and resources — see +ShelfDeduplication.
        results.merge(shelfDuplicates(in: context, container: container, scope: scope)) { $1 }
        return results.filter { $0.value > 0 }
    }

    /// Students, lessons, presentations, work, projects and tracks.
    private static func curriculumDuplicates(
        in context: NSManagedObjectContext,
        container c: NSPersistentCloudKitContainer?,
        scope s: DeduplicationScope
    ) -> [String: Int] {
        var results: [String: Int] = [:]

        // Core models
        results["Student"] = deduplicateStudentsStrong(using: context, container: c, scope: s)
        results["Lesson"] = deduplicateLessonsStrong(using: context, container: c, scope: s)
        // Same name filed twice in one sub-area under two ids — see +LessonNameMerge.
        if s.includes(CDLesson.self) {
            results["Lesson (same name)"] = mergeSameNameLessons(using: context, container: c)
        }
        results["LessonAssignment"] = deduplicate(
            CDLessonAssignment.self, using: context, container: c, scope: s, merge: mergeLessonAssignment
        )
        results["LessonPresentation"] = deduplicateLessonPresentationsStrong(
            using: context, container: c, scope: s
        )

        // Work-related models
        results["WorkModel"] = deduplicateWorkModelsStrong(using: context, container: c, scope: s)
        results["WorkCheckIn"] = deduplicate(
            CDWorkCheckIn.self, using: context, container: c, scope: s, merge: mergeWorkCheckIn
        )
        results["WorkCompletionRecord"] = deduplicate(
            CDWorkCompletionRecord.self, using: context, container: c, scope: s, merge: mergeWorkCompletionRecord
        )
        results["WorkParticipantEntity"] = deduplicate(
            CDWorkParticipantEntity.self, using: context, container: c, scope: s
        )
        results["WorkStep"] = deduplicate(CDWorkStep.self, using: context, container: c, scope: s)

        // CDProject models
        results["Project"] = deduplicate(CDProject.self, using: context, container: c, scope: s)
        results["ProjectRole"] = deduplicate(CDProjectRole.self, using: context, container: c, scope: s)
        results["ProjectSession"] = deduplicate(
            CDProjectSession.self, using: context, container: c, scope: s, merge: mergeProjectSession
        )
        // ProjectAssignmentTemplate, ProjectTemplateWeek, and ProjectWeekRoleAssignment
        // deduplication removed — these entities are deprecated

        // CDTrackEntity models
        results["Track"] = deduplicate(CDTrackEntity.self, using: context, container: c, scope: s)
        // One title defined twice under two ids — see +TrackTitleMerge.
        if s.includes(CDTrackEntity.self) {
            results["Track (same title)"] = mergeSameTitleTracks(using: context, container: c)
        }
        results["TrackStep"] = deduplicate(CDTrackStep.self, using: context, container: c, scope: s)
        results["SequenceTrack"] = deduplicate(CDSequenceTrack.self, using: context, container: c, scope: s)
        results["StudentTrackEnrollment"] = deduplicate(
            CDStudentTrackEnrollmentEntity.self, using: context, container: c, scope: s
        )
        return results
    }

    /// Notes, attendance, calendar, community and the smaller record types.
    private static func recordDuplicates(
        in context: NSManagedObjectContext,
        container c: NSPersistentCloudKitContainer?,
        scope s: DeduplicationScope
    ) -> [String: Int] {
        var results: [String: Int] = [:]

        // Notes and documents
        results["Note"] = deduplicateNotesStrong(using: context, container: c, scope: s)
        results["NoteTemplate"] = deduplicate(CDNoteTemplate.self, using: context, container: c, scope: s)
        results["NoteStudentLink"] = deduplicate(CDNoteStudentLink.self, using: context, container: c, scope: s)
        results["Document"] = deduplicate(CDDocument.self, using: context, container: c, scope: s)

        // Attendance and calendar
        results["AttendanceRecord"] = deduplicateAttendanceRecordsStrong(using: context, scope: s)
        results["StudentMeeting"] = deduplicate(
            CDStudentMeeting.self, using: context, container: c, scope: s, merge: mergeStudentMeeting
        )
        results["MeetingTemplate"] = deduplicate(CDMeetingTemplate.self, using: context, container: c, scope: s)
        results["CalendarEvent"] = deduplicate(CDCalendarEvent.self, using: context, container: c, scope: s)
        results["NonSchoolDay"] = deduplicate(CDNonSchoolDay.self, using: context, container: c, scope: s)
        results["SchoolDayOverride"] = deduplicate(CDSchoolDayOverride.self, using: context, container: c, scope: s)

        // Community models
        results["CommunityTopic"] = deduplicate(CDCommunityTopicEntity.self, using: context, container: c, scope: s)
        results["ProposedSolution"] = deduplicate(
            CDProposedSolutionEntity.self, using: context, container: c, scope: s
        )
        results["CommunityAttachment"] = deduplicate(
            CDCommunityAttachment.self, using: context, container: c, scope: s
        )

        // Other models
        results["Reminder"] = deduplicate(
            CDReminder.self, using: context, container: c, scope: s, merge: mergeReminder
        )
        results["TodoItem"] = deduplicate(CDTodoItem.self, using: context, container: c, scope: s)
        results["TodoSubtask"] = deduplicate(CDTodoSubtask.self, using: context, container: c, scope: s)
        return results
    }
}
