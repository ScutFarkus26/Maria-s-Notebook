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
