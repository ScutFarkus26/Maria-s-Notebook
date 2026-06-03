import Foundation
import CoreData
import os

// MARK: - Deduplication

extension DataCleanupService {

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

            for d in duplicates { context.delete(d) }
            changed = true
        }

        if changed { context.safeSave() }
    }

    // MARK: - Generic Deduplication

    /// Generic deduplication for any NSManagedObject with an id property.
    /// Keeps the first instance encountered and deletes duplicates.
    /// Returns the number of duplicates removed.
    @discardableResult
    static func deduplicate<T: NSManagedObject>(
        _ type: T.Type,
        using context: NSManagedObjectContext,
        merge: ((T, T) -> Void)? = nil
    ) -> Int {
        let fetch = CDFetchRequest(T.self)
        let all: [T]
        do {
            all = try context.fetch(fetch)
        } catch {
            logger.warning("Failed to fetch \(type, privacy: .public): \(error.localizedDescription)")
            return 0
        }

        // Fast duplicate detection pass
        var seen = Set<UUID>()
        var hasDuplicates = false
        for item in all {
            let itemID = item.value(forKey: "id") as? UUID ?? UUID()
            if !seen.insert(itemID).inserted {
                hasDuplicates = true
                break
            }
        }
        guard hasDuplicates else { return 0 }

        // Group by ID
        var byID: [UUID: [T]] = [:]
        for item in all {
            let itemID = item.value(forKey: "id") as? UUID ?? UUID()
            byID[itemID, default: []].append(item)
        }

        var deletedCount = 0

        for (_, items) in byID where items.count > 1 {
            guard let canonical = items.first else { continue }
            for duplicate in items.dropFirst() {
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
    static func deduplicateStudentsStrong(using context: NSManagedObjectContext) -> Int {
        deduplicate(CDStudent.self, using: context, merge: mergeStudent)
    }

    @discardableResult
    static func deduplicateLessonsStrong(using context: NSManagedObjectContext) -> Int {
        deduplicate(CDLesson.self, using: context, merge: mergeLesson)
    }

    @discardableResult
    static func deduplicateLessonPresentationsStrong(using context: NSManagedObjectContext) -> Int {
        deduplicate(CDLessonPresentation.self, using: context, merge: mergeLessonPresentation)
    }

    @discardableResult
    static func deduplicateWorkModelsStrong(using context: NSManagedObjectContext) -> Int {
        deduplicate(CDWorkModel.self, using: context) { canonical, duplicate in
            mergeWorkModel(canonical: canonical, duplicate: duplicate, context: context)
        }
    }

    @discardableResult
    static func deduplicateNotesStrong(using context: NSManagedObjectContext) -> Int {
        deduplicate(CDNote.self, using: context, merge: mergeNote)
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
    /// For each (studentID, day) group it keeps the record with the lowest `id`
    /// string — deterministic, so every device converges on the same survivor —
    /// folds any real attendance mark (non-`unmarked` status + absence reason) from
    /// the duplicates into the survivor so nothing is lost, re-points the
    /// duplicates' notes to the survivor (the `notes` relationship is Cascade-delete,
    /// so moving them first prevents note loss), then deletes the duplicates. The
    /// context-level deletes produce proper CloudKit delete tombstones.
    @discardableResult
    static func deduplicateAttendanceRecordsStrong(using context: NSManagedObjectContext) -> Int {
        let fetch = CDFetchRequest(CDAttendanceRecord.self)
        let all: [CDAttendanceRecord]
        do {
            all = try context.fetch(fetch)
        } catch {
            logger.warning("Failed to fetch attendance records for dedup: \(error.localizedDescription)")
            return 0
        }
        guard !all.isEmpty else { return 0 }

        let calendar = Calendar.current

        // Group by (studentID, normalized calendar day). Records missing a
        // studentID or date can't be safely matched, so leave them untouched.
        var groups: [String: [CDAttendanceRecord]] = [:]
        for record in all {
            guard !record.studentID.isEmpty, let date = record.date else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let key = "\(record.studentID)|\(dayStart.timeIntervalSinceReferenceDate)"
            groups[key, default: []].append(record)
        }

        var deletedCount = 0
        for (_, group) in groups where group.count > 1 {
            // Deterministic survivor: lowest id string, so all devices agree.
            let sorted = group.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
            guard let canonical = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                // Preserve a real attendance mark if the survivor is still unmarked.
                if canonical.status == .unmarked && duplicate.status != .unmarked {
                    canonical.status = duplicate.status
                    canonical.absenceReason = duplicate.absenceReason
                }

                // Re-point notes before deletion. `notes` is Cascade-delete, so
                // deleting the duplicate without moving its notes would destroy
                // them. Setting the inverse moves each note to the survivor.
                if let dupeNotes = duplicate.notes?.allObjects as? [CDNote] {
                    for note in dupeNotes {
                        note.attendanceRecord = canonical
                    }
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

    private static func mergeStudent(canonical: CDStudent, duplicate: CDStudent) {
        if canonical.firstName.isEmpty { canonical.firstName = duplicate.firstName }
        if canonical.lastName.isEmpty { canonical.lastName = duplicate.lastName }
        if canonical.nickname == nil { canonical.nickname = duplicate.nickname }
        if canonical.dateStarted == nil { canonical.dateStarted = duplicate.dateStarted }
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

    private static func mergeLesson(canonical: CDLesson, duplicate: CDLesson) {
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
        if canonical.attendanceRecord == nil { canonical.attendanceRecord = duplicate.attendanceRecord }
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

    // MARK: - Deduplicate All Models

    /// Deduplicates all model types in the database.
    @discardableResult
    static func deduplicateAllModels(using context: NSManagedObjectContext) -> [String: Int] {
        var results: [String: Int] = [:]

        // Core models
        results["Student"] = deduplicateStudentsStrong(using: context)
        results["Lesson"] = deduplicateLessonsStrong(using: context)
        results["LessonAssignment"] = deduplicate(CDLessonAssignment.self, using: context)
        results["LessonPresentation"] = deduplicateLessonPresentationsStrong(using: context)

        // Work-related models
        results["WorkModel"] = deduplicateWorkModelsStrong(using: context)
        results["WorkCheckIn"] = deduplicate(CDWorkCheckIn.self, using: context)
        results["WorkCompletionRecord"] = deduplicate(CDWorkCompletionRecord.self, using: context)
        results["WorkParticipantEntity"] = deduplicate(CDWorkParticipantEntity.self, using: context)
        results["WorkStep"] = deduplicate(CDWorkStep.self, using: context)

        // CDProject models
        results["Project"] = deduplicate(CDProject.self, using: context)
        results["ProjectRole"] = deduplicate(CDProjectRole.self, using: context)
        results["ProjectSession"] = deduplicate(CDProjectSession.self, using: context)
        // ProjectAssignmentTemplate, ProjectTemplateWeek, and ProjectWeekRoleAssignment
        // deduplication removed — these entities are deprecated

        // CDTrackEntity models
        results["Track"] = deduplicate(CDTrackEntity.self, using: context)
        results["TrackStep"] = deduplicate(CDTrackStepEntity.self, using: context)
        results["SequenceTrack"] = deduplicate(CDSequenceTrackEntity.self, using: context)
        results["StudentTrackEnrollment"] = deduplicate(CDStudentTrackEnrollmentEntity.self, using: context)

        // Notes and documents
        results["Note"] = deduplicateNotesStrong(using: context)
        results["NoteTemplate"] = deduplicate(CDNoteTemplateEntity.self, using: context)
        results["NoteStudentLink"] = deduplicate(CDNoteStudentLink.self, using: context)
        results["Document"] = deduplicate(CDDocument.self, using: context)

        // Attendance and calendar
        results["AttendanceRecord"] = deduplicateAttendanceRecordsStrong(using: context)
        results["StudentMeeting"] = deduplicate(CDStudentMeeting.self, using: context)
        results["MeetingTemplate"] = deduplicate(CDMeetingTemplateEntity.self, using: context)
        results["CalendarEvent"] = deduplicate(CDCalendarEvent.self, using: context)
        results["NonSchoolDay"] = deduplicate(CDNonSchoolDay.self, using: context)
        results["SchoolDayOverride"] = deduplicate(CDSchoolDayOverride.self, using: context)

        // Community models
        results["CommunityTopic"] = deduplicate(CDCommunityTopicEntity.self, using: context)
        results["ProposedSolution"] = deduplicate(CDProposedSolutionEntity.self, using: context)
        results["CommunityAttachment"] = deduplicate(CDCommunityAttachmentEntity.self, using: context)

        // Other models
        results["Reminder"] = deduplicate(CDReminder.self, using: context)
        results["TodoItem"] = deduplicate(CDTodoItemEntity.self, using: context)
        results["TodoSubtask"] = deduplicate(CDTodoSubtaskEntity.self, using: context)

        return results.filter { $0.value > 0 }
    }
}
// swiftlint:enable cyclomatic_complexity
