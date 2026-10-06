import Foundation
import CoreData
import CloudKit
import os

// MARK: - Deduplicate Notes, Attendance & Records

nonisolated extension DataCleanupService {

    // swiftlint:disable cyclomatic_complexity
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
    /// day — even when they carry different `id` UUIDs. Two devices marking the same
    /// day before syncing each create their own record, which the id-based pass
    /// cannot detect because every row has a unique id.
    ///
    /// For each (studentID, day) group the copy kept is chosen by identity
    /// (`identityPrecedes`: the lowest id string), the same on every device whatever
    /// edits it has seen. Chosen by content, a device that hadn't yet seen an edit
    /// kept the copy another device deleted, and both deletes synced (bug hunt
    /// 2026-10-05, #1). The ``AttendanceDeduplication/wins(_:over:)`` winner, the
    /// record the grid shows, gives the kept copy its mark (`foldMark`); the day's
    /// notes and planned pickup are read across every copy, and private notes still
    /// linked by id follow. The context-level deletes produce CloudKit tombstones.
    @discardableResult
    static func deduplicateAttendanceRecordsStrong(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
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
            // A record moving out of the classroom share has a copy on each side until
            // the move finishes; deleting either here could leave none (DedupShareBoundary).
            if DedupShareBoundary.spansShare(group, container: container) { continue }
            if DedupSyncState.noCopySent(group, container: container) { continue }
            // Folded only once the day has settled here (`DedupSyncState.stillSettling`).
            if DedupSyncState.stillSettling(group, container: container) { continue }
            deletedCount += foldAttendanceDay(group, container: container, in: context)
        }

        guard deletedCount > 0 else { return 0 }
        return saveFolds(in: context) ? deletedCount : 0
    }

    /// Folds one child's copies of one day into the copy kept by identity and
    /// deletes the rest; returns how many went.
    private static func foldAttendanceDay(
        _ group: [CDAttendanceRecord],
        container: NSPersistentCloudKitContainer?,
        in context: NSManagedObjectContext
    ) -> Int {
        let byIdentity = group.sorted { identityPrecedes($0, $1, container: container) }
        guard let kept = byIdentity.first else { return 0 }
        // The record the grid shows: the read side's rule, identity breaking its ties.
        let winner = byIdentity.reduce(kept) { best, candidate in
            AttendanceDeduplication.wins(candidate, over: best) ? candidate : best
        }
        // The pickup the grid showed, read across every copy before the fold
        // changes one: one still planned on a duplicate (an assistant can plan
        // one on a copy made before the guide's mark arrived) is kept, but not
        // one that Left Early or Back in Class ended on another copy.
        let pickup = AttendanceDeduplication.plannedPickup(among: group)
        if winner !== kept { foldMark(from: winner, onto: kept) }

        for duplicate in byIdentity.dropFirst() {
            // Keep the duplicate's note: two devices can each have written
            // one on their own copy of the day.
            kept.note = AttendanceNoteMove.merged(kept.note, duplicate.note)

            // Re-point any private note still linked by id (an older build
            // on another device can write one until it updates) so
            // `AttendanceNoteMove` finds it on the survivor.
            if let duplicateID = duplicate.id?.uuidString {
                let linked = CDFetchRequest(CDNote.self)
                linked.predicate = NSPredicate(format: "attendanceRecordID == %@", duplicateID)
                for note in context.safeFetch(linked) {
                    note.attendanceRecordID = kept.id?.uuidString
                }
            }
            context.delete(duplicate)
        }
        kept.leavesAt = pickup
        return byIdentity.count - 1
    }

    /// Gives the kept copy the winner's mark and who made it, raw: a status a
    /// newer build added reads as unmarked here, and the typed setter would have
    /// written that (#42). `modifiedAt` only moves forward, so a device that
    /// hasn't seen the kept copy's latest change never dates it earlier; a mark
    /// that wins by kind (any mark over none, a person's over Close Arrival's)
    /// is copied even when older, as the grid already shows it.
    private static func foldMark(from winner: CDAttendanceRecord, onto kept: CDAttendanceRecord) {
        kept.statusRaw = winner.statusRaw
        kept.absenceReasonRaw = winner.absenceReasonRaw
        kept.markedAt = winner.markedAt
        kept.leftAt = winner.leftAt
        kept.returnedAt = winner.returnedAt
        kept.statusBeforeLeavingRaw = winner.statusBeforeLeavingRaw
        kept.recordedBy = winner.recordedBy
        kept.recordedByID = winner.recordedByID
        kept.recordedByName = winner.recordedByName
        if let stamp = winner.modifiedAt, stamp > (kept.modifiedAt ?? .distantPast) {
            kept.modifiedAt = stamp
        }
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
        if canonical.practiceSession == nil { canonical.practiceSession = duplicate.practiceSession }
        if canonical.issue == nil { canonical.issue = duplicate.issue }
        if canonical.goingOutID == nil { canonical.goingOutID = duplicate.goingOutID }
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

    static func mergeStudentMeeting(canonical: CDStudentMeeting, duplicate: CDStudentMeeting) {
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

    /// A todo's subtasks cascade with the copy that holds them (#12).
    static func mergeTodoItem(canonical: CDTodoItem, duplicate: CDTodoItem) {
        var existingSubtaskIDs = Set((canonical.subtasks as? Set<CDTodoSubtask>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.subtasks,
            addTo: canonical,
            relationshipKey: "subtasks",
            existingIDs: &existingSubtaskIDs,
            setter: { (subtask: CDTodoSubtask) in subtask.todo = canonical }
        )
    }

    /// A topic's proposed solutions and attachments cascade with the copy that
    /// holds them (#12).
    static func mergeCommunityTopic(canonical: CDCommunityTopicEntity, duplicate: CDCommunityTopicEntity) {
        let solutions = canonical.proposedSolutions as? Set<CDProposedSolutionEntity>
        var existingSolutionIDs = Set(solutions?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.proposedSolutions,
            addTo: canonical,
            relationshipKey: "proposedSolutions",
            existingIDs: &existingSolutionIDs,
            setter: { (solution: CDProposedSolutionEntity) in solution.topic = canonical }
        )
        var existingAttachmentIDs = Set((canonical.attachments as? Set<CDCommunityAttachment>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.attachments,
            addTo: canonical,
            relationshipKey: "attachments",
            existingIDs: &existingAttachmentIDs,
            setter: { (attachment: CDCommunityAttachment) in attachment.topic = canonical }
        )
    }

    static func mergeReminder(canonical: CDReminder, duplicate: CDReminder) {
        var existingNoteIDs = Set((canonical.noteItems as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.noteItems,
            addTo: canonical,
            relationshipKey: "noteItems",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.reminder = canonical }
        )
    }
}
// swiftlint:enable cyclomatic_complexity
