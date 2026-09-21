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

    // swiftlint:disable cyclomatic_complexity
    /// Deduplicate draft CDLessonAssignment records that refer to the same lesson and identical student set.
    /// Keeps the earliest `createdAt` as canonical, merges flags, and deletes the rest.
    static func deduplicateDraftLessonAssignments(using context: NSManagedObjectContext) {
        let draftRaw = LessonAssignmentState.draft.rawValue
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "stateRaw == %@", draftRaw)
        let candidates = context.safeFetch(request)
        guard !candidates.isEmpty else { return }

        // Group by (lessonID + sorted studentIDs)
        let groups = candidates.grouped { la -> String in
            let sortedIDs = la.studentIDs.sorted()
            return la.lessonID + "|" + sortedIDs.joined(separator: ",")
        }

        var changed = false
        for (_, sequence) in groups {
            guard sequence.count > 1 else { continue }
            guard let canonical = sequence.sorted(by: { lhs, rhs in
                let lhsDate = lhs.createdAt ?? Date.distantPast
                let rhsDate = rhs.createdAt ?? Date.distantPast
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return (lhs.id ?? UUID()).uuidString < (rhs.id ?? UUID()).uuidString
            }).first else { continue }
            let duplicates = sequence.filter { $0.id != canonical.id }

            if duplicates.contains(where: { $0.needsPractice }) {
                canonical.needsPractice = true
            }
            if duplicates.contains(where: { $0.needsAnotherPresentation }) {
                canonical.needsAnotherPresentation = true
            }
            if canonical.notes.trimmed().isEmpty {
                if let firstNote = duplicates.map({ $0.notes }).first(where: { !$0.trimmed().isEmpty }) {
                    canonical.notes = firstNote
                }
            }
            if canonical.followUpWork.trimmed().isEmpty {
                if let firstFU = duplicates.map({ $0.followUpWork }).first(where: { !$0.trimmed().isEmpty }) {
                    canonical.followUpWork = firstFU
                }
            }

            for d in duplicates {
                // Re-parent the duplicate's notes onto the survivor first —
                // unifiedNotes is a Cascade relationship, so a raw delete would
                // destroy any observation notes attached to the duplicate draft.
                mergeLessonAssignment(canonical: canonical, duplicate: d)
                context.delete(d)
            }
            changed = true
        }

        if changed { context.safeSave() }
    }

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

    // MARK: - Strong Deduplication (Data-Preserving Merges)

    @discardableResult
    static func deduplicateStudentsStrong(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> Int {
        deduplicate(CDStudent.self, using: context, container: container, scope: scope, merge: mergeStudent)
    }

    @discardableResult
    static func deduplicateLessonsStrong(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> Int {
        deduplicate(CDLesson.self, using: context, container: container, scope: scope, merge: mergeLesson)
    }

    @discardableResult
    static func deduplicateLessonPresentationsStrong(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> Int {
        deduplicate(
            CDLessonPresentation.self, using: context, container: container, scope: scope,
            merge: mergeLessonPresentation
        )
    }

    @discardableResult
    static func deduplicateWorkModelsStrong(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> Int {
        deduplicate(CDWorkModel.self, using: context, container: container, scope: scope) { canonical, duplicate in
            mergeWorkModel(canonical: canonical, duplicate: duplicate, context: context)
        }
    }

    @discardableResult
    static func deduplicateNotesStrong(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> Int {
        deduplicate(CDNote.self, using: context, container: container, scope: scope, merge: mergeNote)
    }

    /// Semantic deduplication for attendance records.
    ///
    /// Unlike the generic id-based `deduplicate(_:)`, this collapses records that
    /// represent the *same logical fact* — one student's attendance on one calendar
    /// day — even when they carry different `id` UUIDs. Repeated CloudKit re-imports
    /// can create several such rows (each a distinct CloudKit record) for a single
    /// student/day, which the id-based pass cannot detect because every row has a
    /// unique id.
    ///
    /// For each (studentID, day) group it keeps the ``AttendanceDeduplication/wins(_:over:)``
    /// winner — the same deterministic ordering the read-side `deduplicatedPerStudentDay()`
    /// uses, so the record the grid was already showing is the one that survives —
    /// folds any real attendance mark (non-`unmarked` status + absence reason) from
    /// the duplicates into the survivor so nothing is lost, re-points the
    /// duplicates' notes to the survivor (the `notes` relationship is Cascade-delete,
    /// so moving them first prevents note loss), then deletes the duplicates. The
    /// context-level deletes produce proper CloudKit delete tombstones.
    @discardableResult
    static func deduplicateAttendanceRecordsStrong(
        using context: NSManagedObjectContext,
        scope: DeduplicationScope = .everything
    ) -> Int {
        guard scope.includes(CDAttendanceRecord.self) else { return 0 }

        // Cheap pre-check: read only the two columns that make up the grouping key
        // to learn whether any (student, day) repeats at all. This runs on every
        // launch and after every CloudKit import, and the answer is almost always
        // "no" — finding that out shouldn't fault the whole table into the context.
        // `nil` means the pre-check couldn't be trusted, so fall back to the full pass.
        if let hasDuplicates = attendanceHasRepeatedStudentDay(in: context), !hasDuplicates {
            return 0
        }

        let fetch = CDFetchRequest(CDAttendanceRecord.self)
        let all: [CDAttendanceRecord]
        do {
            all = try context.fetch(fetch)
        } catch {
            logger.warning("Failed to fetch attendance records for dedup: \(error.localizedDescription)")
            return 0
        }
        guard !all.isEmpty else { return 0 }

        // Group by (studentID, normalized calendar day). Records missing a
        // studentID or date can't be safely matched, so leave them untouched.
        var groups: [String: [CDAttendanceRecord]] = [:]
        for record in all {
            guard let key = attendanceGroupKey(studentID: record.studentID, date: record.date) else { continue }
            groups[key, default: []].append(record)
        }

        var deletedCount = 0
        for (_, group) in groups where group.count > 1 {
            // Deterministic survivor: the shared comparator's winner, so all
            // devices — and the read-side dedup — agree on the same record.
            let sorted = group.sorted { AttendanceDeduplication.wins($0, over: $1) }
            guard let canonical = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                // Preserve a real attendance mark if the survivor is still unmarked.
                // (The comparator already prefers marked records, so this only fires
                // for groups that are entirely unmarked — where it's a no-op — but it
                // stays as a belt-and-braces guard against comparator drift.)
                if canonical.status == .unmarked && duplicate.status != .unmarked {
                    canonical.status = duplicate.status
                    canonical.absenceReason = duplicate.absenceReason
                }

                // Re-point notes before deletion. Nothing cascades now that the
                // link is a string FK, so notes would simply dangle on a
                // deleted record's id if they weren't moved to the survivor.
                for note in duplicate.unifiedNotes {
                    note.attendanceRecordID = canonical.id?.uuidString
                }

                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            context.safeSave()
        }
        return deletedCount
    }

    /// The (student, calendar day) identity two attendance rows must share to be
    /// duplicates of one another. `nil` for a row that can't be matched safely —
    /// no student id, or no date.
    ///
    /// Both the pre-check and the full pass build their groups through this, so the
    /// two can never disagree about what counts as the same logical fact.
    private static func attendanceGroupKey(studentID: String, date: Date?) -> String? {
        guard !studentID.isEmpty, let date else { return nil }
        let dayStart = AppCalendar.shared.startOfDay(for: date)
        return "\(studentID)|\(dayStart.timeIntervalSinceReferenceDate)"
    }

    /// Whether any (studentID, day) appears on more than one attendance row, found
    /// by reading just the two grouping columns instead of materializing every record.
    ///
    /// Returns `nil` when the answer can't be trusted — a context with unsaved
    /// changes (dictionary-result fetches don't see pending inserts) or a failed
    /// fetch — in which case the caller should do the original full pass.
    private static func attendanceHasRepeatedStudentDay(in context: NSManagedObjectContext) -> Bool? {
        guard !context.hasChanges else { return nil }
        guard let entityName = CDFetchRequest(CDAttendanceRecord.self).entityName else { return nil }

        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["studentID", "date"]

        let rows: [NSDictionary]
        do {
            rows = try context.fetch(request)
        } catch {
            return nil
        }

        var seen = Set<String>(minimumCapacity: rows.count)
        for row in rows {
            let key = attendanceGroupKey(studentID: row["studentID"] as? String ?? "",
                                         date: row["date"] as? Date)
            guard let key else { continue }
            if !seen.insert(key).inserted { return true }
        }
        return false
    }

    private static func mergeStudent(canonical: CDStudent, duplicate: CDStudent) {
        if canonical.firstName.isEmpty { canonical.firstName = duplicate.firstName }
        if canonical.lastName.isEmpty { canonical.lastName = duplicate.lastName }
        if canonical.nickname == nil { canonical.nickname = duplicate.nickname }
        if canonical.dateStarted == nil { canonical.dateStarted = duplicate.dateStarted }
        if canonical.previousLevelRaw == nil { canonical.previousLevelRaw = duplicate.previousLevelRaw }
        if canonical.dateLastPromoted == nil { canonical.dateLastPromoted = duplicate.dateLastPromoted }
        if canonical.manualOrder == 0 && duplicate.manualOrder != 0 { canonical.manualOrder = duplicate.manualOrder }

        // nextLessons is a Transformable [String] stored as NSObject
        let canonicalNext = canonical.nextLessonsArray
        let duplicateNext = duplicate.nextLessonsArray
        if canonicalNext.isEmpty && !duplicateNext.isEmpty {
            canonical.nextLessons = duplicateNext as NSObject
        } else if !canonicalNext.isEmpty && !duplicateNext.isEmpty {
            let merged = Array(Set(canonicalNext).union(duplicateNext))
            canonical.nextLessons = merged as NSObject
        }

        // Re-point duplicate's documents to canonical student via FK
        let existingDocIDs = Set(canonical.documents.compactMap(\.id))
        for doc in duplicate.documents where doc.id == nil || !existingDocIDs.contains(doc.id!) {
            doc.student = canonical
        }
    }

    static func mergeLesson(canonical: CDLesson, duplicate: CDLesson) {
        if canonical.name.isEmpty { canonical.name = duplicate.name }
        if canonical.area.isEmpty { canonical.area = duplicate.area }
        if canonical.sequence.isEmpty { canonical.sequence = duplicate.sequence }
        if canonical.section.isEmpty { canonical.section = duplicate.section }
        if canonical.writeUp.isEmpty { canonical.writeUp = duplicate.writeUp }
        if canonical.orderInSequence == 0 && duplicate.orderInSequence != 0 {
            canonical.orderInSequence = duplicate.orderInSequence
        }
        if canonical.sortIndex == 0 && duplicate.sortIndex != 0 { canonical.sortIndex = duplicate.sortIndex }
        if canonical.pagesFileBookmark == nil { canonical.pagesFileBookmark = duplicate.pagesFileBookmark }
        if canonical.pagesFileRelativePath == nil { canonical.pagesFileRelativePath = duplicate.pagesFileRelativePath }
        if canonical.personalKindRaw == nil { canonical.personalKindRaw = duplicate.personalKindRaw }
        if canonical.defaultWorkKindRaw == nil { canonical.defaultWorkKindRaw = duplicate.defaultWorkKindRaw }

        // Re-point duplicate lesson's notes to canonical via FK
        if let dupID = duplicate.id?.uuidString, let ctx = canonical.managedObjectContext {
            let noteReq = CDFetchRequest(CDNote.self)
            noteReq.predicate = NSPredicate(format: "lessonID == %@", dupID)
            for note in (try? ctx.fetch(noteReq)) ?? [] {
                note.lesson = canonical
            }

            // Re-point duplicate lesson's assignments to canonical via FK
            let laReq = CDFetchRequest(CDLessonAssignment.self)
            laReq.predicate = NSPredicate(format: "lessonID == %@", dupID)
            for la in (try? ctx.fetch(laReq)) ?? [] {
                la.lesson = canonical
            }
        }
    }

    private static func mergeLessonPresentation(canonical: CDLessonPresentation, duplicate: CDLessonPresentation) {
        if canonical.studentID.isEmpty { canonical.studentID = duplicate.studentID }
        if canonical.lessonID.isEmpty { canonical.lessonID = duplicate.lessonID }
        if canonical.presentationID == nil { canonical.presentationID = duplicate.presentationID }
        if canonical.trackID == nil { canonical.trackID = duplicate.trackID }
        if canonical.trackStepID == nil { canonical.trackStepID = duplicate.trackStepID }
        if canonical.lastObservedAt == nil { canonical.lastObservedAt = duplicate.lastObservedAt }
        if canonical.masteredAt == nil { canonical.masteredAt = duplicate.masteredAt }
        if (canonical.notes ?? "").isEmpty { canonical.notes = duplicate.notes }

        // Follow-up is one conflict-resolution bundle. Mixing an older action with
        // a newer resolution can accidentally reopen a responsibility on another
        // shared device, so copy every field from whichever bundle was updated last.
        let canonicalFollowUpDate = canonical.followUpUpdatedAt ?? .distantPast
        let duplicateFollowUpDate = duplicate.followUpUpdatedAt ?? .distantPast
        if duplicateFollowUpDate > canonicalFollowUpDate
            || (canonical.followUpActionRaw == nil && duplicate.followUpActionRaw != nil) {
            canonical.followUpActionRaw = duplicate.followUpActionRaw
            canonical.followUpReviewAt = duplicate.followUpReviewAt
            canonical.followUpResolvedAt = duplicate.followUpResolvedAt
            canonical.followUpResolutionRaw = duplicate.followUpResolutionRaw
            canonical.followUpUpdatedAt = duplicate.followUpUpdatedAt
            canonical.followUpEvidenceRaw = duplicate.followUpEvidenceRaw
            canonical.followUpNote = duplicate.followUpNote
            canonical.followUpSupportRaw = duplicate.followUpSupportRaw
        }
    }

    private static func mergeWorkModel(
        canonical: CDWorkModel,
        duplicate: CDWorkModel,
        context: NSManagedObjectContext
    ) {
        if canonical.title.isEmpty { canonical.title = duplicate.title }
        let dupNoteText = duplicate.latestUnifiedNoteText.trimmed()
        if canonical.latestUnifiedNoteText.trimmed().isEmpty && !dupNoteText.isEmpty {
            canonical.setLegacyNoteText(dupNoteText, in: context)
        }
        if canonical.completedAt == nil { canonical.completedAt = duplicate.completedAt }
        if canonical.lastTouchedAt == nil { canonical.lastTouchedAt = duplicate.lastTouchedAt }
        if canonical.dueAt == nil { canonical.dueAt = duplicate.dueAt }
        if canonical.completionOutcomeRaw == nil { canonical.completionOutcomeRaw = duplicate.completionOutcomeRaw }
        if canonical.studentID.isEmpty { canonical.studentID = duplicate.studentID }
        if canonical.lessonID.isEmpty { canonical.lessonID = duplicate.lessonID }
        if canonical.presentationID == nil { canonical.presentationID = duplicate.presentationID }
        if canonical.trackID == nil { canonical.trackID = duplicate.trackID }
        if canonical.trackStepID == nil { canonical.trackStepID = duplicate.trackStepID }
        if canonical.scheduledNote == nil { canonical.scheduledNote = duplicate.scheduledNote }
        if canonical.scheduledReasonRaw == nil { canonical.scheduledReasonRaw = duplicate.scheduledReasonRaw }
        if canonical.sourceContextTypeRaw == nil { canonical.sourceContextTypeRaw = duplicate.sourceContextTypeRaw }
        if canonical.sourceContextID == nil { canonical.sourceContextID = duplicate.sourceContextID }

        let rawParticipants = canonical.participants as? Set<CDWorkParticipantEntity>
        var existingParticipantIDs = Set(rawParticipants?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.participants,
            addTo: canonical,
            relationshipKey: "participants",
            existingIDs: &existingParticipantIDs,
            setter: { (p: CDWorkParticipantEntity) in p.work = canonical }
        )

        var existingCheckInIDs = Set((canonical.checkIns as? Set<CDWorkCheckIn>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.checkIns,
            addTo: canonical,
            relationshipKey: "checkIns",
            existingIDs: &existingCheckInIDs,
            setter: { (ci: CDWorkCheckIn) in ci.work = canonical; ci.workID = (canonical.id ?? UUID()).uuidString }
        )

        var existingStepIDs = Set((canonical.steps as? Set<CDWorkStep>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.steps,
            addTo: canonical,
            relationshipKey: "steps",
            existingIDs: &existingStepIDs,
            setter: { (step: CDWorkStep) in step.work = canonical }
        )

        var existingNoteIDs = Set((canonical.unifiedNotes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.unifiedNotes,
            addTo: canonical,
            relationshipKey: "unifiedNotes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.work = canonical }
        )
    }

    private static func mergeNote(canonical: CDNote, duplicate: CDNote) {
        if canonical.body.isEmpty { canonical.body = duplicate.body }
        if !canonical.isPinned && duplicate.isPinned { canonical.isPinned = true }
        if !canonical.includeInReport && duplicate.includeInReport { canonical.includeInReport = true }
        if canonical.imagePath == nil || canonical.imagePath?.isEmpty == true {
            canonical.imagePath = duplicate.imagePath
        }
        if canonical.reportedBy == nil { canonical.reportedBy = duplicate.reportedBy }
        if canonical.reporterName == nil { canonical.reporterName = duplicate.reporterName }

        // Merge relationships (parent entities)
        if canonical.lesson == nil { canonical.lesson = duplicate.lesson }
        if canonical.work == nil { canonical.work = duplicate.work }
        if canonical.lessonAssignment == nil { canonical.lessonAssignment = duplicate.lessonAssignment }
        if canonical.attendanceRecordID == nil { canonical.attendanceRecordID = duplicate.attendanceRecordID }
        if canonical.workCheckIn == nil { canonical.workCheckIn = duplicate.workCheckIn }
        if canonical.workCompletionRecord == nil { canonical.workCompletionRecord = duplicate.workCompletionRecord }
        if canonical.studentMeeting == nil { canonical.studentMeeting = duplicate.studentMeeting }
        if canonical.projectSession == nil { canonical.projectSession = duplicate.projectSession }
        if canonical.communityTopic == nil { canonical.communityTopic = duplicate.communityTopic }
        if canonical.reminder == nil { canonical.reminder = duplicate.reminder }
        if canonical.schoolDayOverride == nil { canonical.schoolDayOverride = duplicate.schoolDayOverride }
        if canonical.studentTrackEnrollment == nil {
            canonical.studentTrackEnrollment = duplicate.studentTrackEnrollment
        }

        var existingLinkIDs = Set((canonical.studentLinks as? Set<CDNoteStudentLink>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.studentLinks,
            addTo: canonical,
            relationshipKey: "studentLinks",
            existingIDs: &existingLinkIDs,
            setter: { (link: CDNoteStudentLink) in
                link.note = canonical
                link.noteID = (canonical.id ?? UUID()).uuidString
            }
        )
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

    private static func mergeLessonAssignment(canonical: CDLessonAssignment, duplicate: CDLessonAssignment) {
        var existingNoteIDs = Set((canonical.unifiedNotes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.unifiedNotes,
            addTo: canonical,
            relationshipKey: "unifiedNotes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.lessonAssignment = canonical }
        )
    }

    private static func mergeWorkCheckIn(canonical: CDWorkCheckIn, duplicate: CDWorkCheckIn) {
        var existingNoteIDs = Set((canonical.notes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.notes,
            addTo: canonical,
            relationshipKey: "notes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.workCheckIn = canonical }
        )
    }

    private static func mergeWorkCompletionRecord(canonical: CDWorkCompletionRecord, duplicate: CDWorkCompletionRecord) {
        var existingNoteIDs = Set((canonical.notes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.notes,
            addTo: canonical,
            relationshipKey: "notes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.workCompletionRecord = canonical }
        )
    }

    private static func mergeProjectSession(canonical: CDProjectSession, duplicate: CDProjectSession) {
        var existingNoteIDs = Set((canonical.noteItems as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.noteItems,
            addTo: canonical,
            relationshipKey: "noteItems",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.projectSession = canonical }
        )
    }

    private static func mergeStudentMeeting(canonical: CDStudentMeeting, duplicate: CDStudentMeeting) {
        var existingNoteIDs = Set((canonical.notes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.notes,
            addTo: canonical,
            relationshipKey: "notes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.studentMeeting = canonical }
        )
        var existingReviewIDs = Set((canonical.workReviews as? Set<CDMeetingWorkReview>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.workReviews,
            addTo: canonical,
            relationshipKey: "workReviews",
            existingIDs: &existingReviewIDs,
            setter: { (review: CDMeetingWorkReview) in review.meeting = canonical }
        )
    }

    private static func mergeReminder(canonical: CDReminder, duplicate: CDReminder) {
        var existingNoteIDs = Set((canonical.noteItems as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.noteItems,
            addTo: canonical,
            relationshipKey: "noteItems",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.reminder = canonical }
        )
    }

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
// swiftlint:enable cyclomatic_complexity
