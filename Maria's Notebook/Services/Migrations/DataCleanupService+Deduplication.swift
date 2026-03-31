import Foundation
import CoreData
import os

// MARK: - Deduplication

extension DataCleanupService {

    // swiftlint:disable cyclomatic_complexity
    /// Deduplicate draft LessonAssignment records that refer to the same lesson and identical student set.
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
        for (_, group) in groups {
            guard group.count > 1 else { continue }
            guard let canonical = group.sorted(by: { lhs, rhs in
                let lhsDate = lhs.createdAt ?? Date.distantPast
                let rhsDate = rhs.createdAt ?? Date.distantPast
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return (lhs.id ?? UUID()).uuidString < (rhs.id ?? UUID()).uuidString
            }).first else { continue }
            let duplicates = group.filter { $0.id != canonical.id }

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

        // Merge documents relationship (NSSet)
        var existingDocIDs = Set((canonical.documents as? Set<CDDocument>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.documents,
            addTo: canonical,
            relationshipKey: "documents",
            existingIDs: &existingDocIDs,
            setter: { (doc: CDDocument) in doc.student = canonical }
        )
    }

    private static func mergeLesson(canonical: CDLesson, duplicate: CDLesson) {
        if canonical.name.isEmpty { canonical.name = duplicate.name }
        if canonical.subject.isEmpty { canonical.subject = duplicate.subject }
        if canonical.group.isEmpty { canonical.group = duplicate.group }
        if canonical.subheading.isEmpty { canonical.subheading = duplicate.subheading }
        if canonical.writeUp.isEmpty { canonical.writeUp = duplicate.writeUp }
        if canonical.orderInGroup == 0 && duplicate.orderInGroup != 0 {
            canonical.orderInGroup = duplicate.orderInGroup
        }
        if canonical.sortIndex == 0 && duplicate.sortIndex != 0 { canonical.sortIndex = duplicate.sortIndex }
        if canonical.pagesFileBookmark == nil { canonical.pagesFileBookmark = duplicate.pagesFileBookmark }
        if canonical.pagesFileRelativePath == nil { canonical.pagesFileRelativePath = duplicate.pagesFileRelativePath }
        if canonical.personalKindRaw == nil { canonical.personalKindRaw = duplicate.personalKindRaw }
        if canonical.defaultWorkKindRaw == nil { canonical.defaultWorkKindRaw = duplicate.defaultWorkKindRaw }

        var existingNoteIDs = Set((canonical.notes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.notes,
            addTo: canonical,
            relationshipKey: "notes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.lesson = canonical }
        )

        var existingLAIDs = Set((canonical.lessonAssignments as? Set<CDLessonAssignment>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.lessonAssignments,
            addTo: canonical,
            relationshipKey: "lessonAssignments",
            existingIDs: &existingLAIDs,
            setter: { (la: CDLessonAssignment) in la.lesson = canonical }
        )
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

    private static func mergeWorkModel(canonical: CDWorkModel, duplicate: CDWorkModel, context: NSManagedObjectContext) {
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
        if canonical.legacyStudentLessonID == nil { canonical.legacyStudentLessonID = duplicate.legacyStudentLessonID }

        var existingParticipantIDs = Set((canonical.participants as? Set<CDWorkParticipantEntity>)?.compactMap(\.id) ?? [])
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

        // Project models
        results["Project"] = deduplicate(CDProject.self, using: context)
        results["ProjectRole"] = deduplicate(CDProjectRole.self, using: context)
        results["ProjectSession"] = deduplicate(CDProjectSession.self, using: context)
        results["ProjectAssignmentTemplate"] = deduplicate(CDProjectAssignmentTemplate.self, using: context)
        results["ProjectTemplateWeek"] = deduplicate(CDProjectTemplateWeek.self, using: context)
        results["ProjectWeekRoleAssignment"] = deduplicate(CDProjectWeekRoleAssignment.self, using: context)

        // Track models
        results["Track"] = deduplicate(CDTrackEntity.self, using: context)
        results["TrackStep"] = deduplicate(CDTrackStepEntity.self, using: context)
        results["GroupTrack"] = deduplicate(CDGroupTrackEntity.self, using: context)
        results["StudentTrackEnrollment"] = deduplicate(CDStudentTrackEnrollmentEntity.self, using: context)

        // Notes and documents
        results["Note"] = deduplicateNotesStrong(using: context)
        results["NoteTemplate"] = deduplicate(CDNoteTemplateEntity.self, using: context)
        results["NoteStudentLink"] = deduplicate(CDNoteStudentLink.self, using: context)
        results["Document"] = deduplicate(CDDocument.self, using: context)

        // Attendance and calendar
        results["AttendanceRecord"] = deduplicate(CDAttendanceRecord.self, using: context)
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

        return results.filter { $0.value > 0 }
    }
}
// swiftlint:enable cyclomatic_complexity
