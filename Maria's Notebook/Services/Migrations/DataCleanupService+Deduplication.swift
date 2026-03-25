import Foundation
import SwiftData
import os

// MARK: - Deduplication

extension DataCleanupService {

    // swiftlint:disable cyclomatic_complexity
    /// Deduplicate draft LessonAssignment records that refer to the same lesson and identical student set.
    /// Keeps the earliest `createdAt` as canonical, merges flags, and deletes the rest.
    static func deduplicateDraftLessonAssignments(using context: ModelContext) {
        let draftRaw = LessonAssignmentState.draft.rawValue
        let descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.stateRaw == draftRaw })
        let candidates = context.safeFetch(descriptor)
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
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
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

    /// Generic deduplication for any PersistentModel with an id property.
    /// Keeps the first instance encountered and deletes duplicates.
    /// Returns the number of duplicates removed.
    @discardableResult
    static func deduplicate<T: PersistentModel & Identifiable>(
        _ type: T.Type,
        using context: ModelContext,
        merge: ((T, T) -> Void)? = nil
    ) -> Int where T.ID == UUID {
        let fetch = FetchDescriptor<T>()
        // Fetch raw without deduplication to find actual duplicates in the database
        let all: [T]
        do {
            all = try context.fetch(fetch)
        } catch {
            logger.warning("Failed to fetch \(type, privacy: .public): \(error.localizedDescription)")
            return 0
        }

        // Fast duplicate detection pass (avoids extra work if no duplicates exist)
        var seen = Set<UUID>()
        var hasDuplicates = false
        for item in all where !seen.insert(item.id).inserted {
            hasDuplicates = true
            break
        }
        guard hasDuplicates else { return 0 }

        // Group by ID (only when duplicates exist)
        var byID: [UUID: [T]] = [:]
        for item in all {
            byID[item.id, default: []].append(item)
        }

        var deletedCount = 0

        // For each group with duplicates, keep the first and delete the rest
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

    // MARK: - Merge Helpers

    static func mergeRelationship<T: Identifiable>(
        from source: [T]?,
        to destination: inout [T]?,
        setter: (T) -> Void
    ) where T.ID == UUID {
        guard let sourceItems = source, !sourceItems.isEmpty else { return }
        if destination == nil { destination = [] }
        var existingIDs = Set((destination ?? []).map(\.id))
        for item in sourceItems {
            setter(item)
            if existingIDs.insert(item.id).inserted {
                destination?.append(item)
            }
        }
    }

    // MARK: - Strong Deduplication (Data-Preserving Merges)

    @discardableResult
    static func deduplicateStudentsStrong(using context: ModelContext) -> Int {
        deduplicate(Student.self, using: context, merge: mergeStudent)
    }

    @discardableResult
    static func deduplicateLessonsStrong(using context: ModelContext) -> Int {
        deduplicate(Lesson.self, using: context, merge: mergeLesson)
    }

    @discardableResult
    static func deduplicateLessonPresentationsStrong(using context: ModelContext) -> Int {
        deduplicate(LessonPresentation.self, using: context, merge: mergeLessonPresentation)
    }

    @discardableResult
    static func deduplicateWorkModelsStrong(using context: ModelContext) -> Int {
        deduplicate(WorkModel.self, using: context) { canonical, duplicate in
            mergeWorkModel(canonical: canonical, duplicate: duplicate, context: context)
        }
    }

    @discardableResult
    static func deduplicateNotesStrong(using context: ModelContext) -> Int {
        deduplicate(Note.self, using: context, merge: mergeNote)
    }

    private static func mergeStudent(canonical: Student, duplicate: Student) {
        if canonical.firstName.isEmpty { canonical.firstName = duplicate.firstName }
        if canonical.lastName.isEmpty { canonical.lastName = duplicate.lastName }
        if canonical.nickname == nil { canonical.nickname = duplicate.nickname }
        if canonical.dateStarted == nil { canonical.dateStarted = duplicate.dateStarted }
        if canonical.manualOrder == 0 && duplicate.manualOrder != 0 { canonical.manualOrder = duplicate.manualOrder }

        if canonical.nextLessons.isEmpty {
            canonical.nextLessons = duplicate.nextLessons
        } else if !duplicate.nextLessons.isEmpty {
            canonical.nextLessons = Array(Set(canonical.nextLessons).union(duplicate.nextLessons))
        }

        mergeRelationship(from: duplicate.documents, to: &canonical.documents, setter: { $0.student = canonical })
    }

    private static func mergeLesson(canonical: Lesson, duplicate: Lesson) {
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

        mergeRelationship(from: duplicate.notes, to: &canonical.notes, setter: { $0.lesson = canonical })
        // Legacy relationship removed -- fully migrated to LessonAssignment
        mergeRelationship(
            from: duplicate.lessonAssignments,
            to: &canonical.lessonAssignments,
            setter: { $0.lesson = canonical }
        )
    }

    private static func mergeLessonPresentation(canonical: LessonPresentation, duplicate: LessonPresentation) {
        if canonical.studentID.isEmpty { canonical.studentID = duplicate.studentID }
        if canonical.lessonID.isEmpty { canonical.lessonID = duplicate.lessonID }
        if canonical.presentationID == nil { canonical.presentationID = duplicate.presentationID }
        if canonical.trackID == nil { canonical.trackID = duplicate.trackID }
        if canonical.trackStepID == nil { canonical.trackStepID = duplicate.trackStepID }
        if canonical.lastObservedAt == nil { canonical.lastObservedAt = duplicate.lastObservedAt }
        if canonical.masteredAt == nil { canonical.masteredAt = duplicate.masteredAt }
        if (canonical.notes ?? "").isEmpty { canonical.notes = duplicate.notes }
    }

    private static func mergeWorkModel(canonical: WorkModel, duplicate: WorkModel, context: ModelContext) {
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

        mergeRelationship(from: duplicate.participants, to: &canonical.participants, setter: { $0.work = canonical })
        mergeRelationship(
            from: duplicate.checkIns,
            to: &canonical.checkIns,
            setter: { $0.work = canonical; $0.workID = canonical.id.uuidString }
        )
        mergeRelationship(from: duplicate.steps, to: &canonical.steps, setter: { $0.work = canonical })
        mergeRelationship(from: duplicate.unifiedNotes, to: &canonical.unifiedNotes, setter: { $0.work = canonical })
    }

    private static func mergeNote(canonical: Note, duplicate: Note) {
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
        // Legacy relationship removed -- fully migrated to LessonAssignment
        if canonical.lessonAssignment == nil { canonical.lessonAssignment = duplicate.lessonAssignment }
        if canonical.attendanceRecord == nil { canonical.attendanceRecord = duplicate.attendanceRecord }
        if canonical.workCheckIn == nil { canonical.workCheckIn = duplicate.workCheckIn }
        if canonical.workCompletionRecord == nil { canonical.workCompletionRecord = duplicate.workCompletionRecord }
        // workPlanItem removed in Phase 6 - migrated to WorkCheckIn
        if canonical.studentMeeting == nil { canonical.studentMeeting = duplicate.studentMeeting }
        if canonical.projectSession == nil { canonical.projectSession = duplicate.projectSession }
        if canonical.communityTopic == nil { canonical.communityTopic = duplicate.communityTopic }
        if canonical.reminder == nil { canonical.reminder = duplicate.reminder }
        if canonical.schoolDayOverride == nil { canonical.schoolDayOverride = duplicate.schoolDayOverride }
        if canonical.studentTrackEnrollment == nil {
            canonical.studentTrackEnrollment = duplicate.studentTrackEnrollment
        }

        mergeRelationship(
            from: duplicate.studentLinks,
            to: &canonical.studentLinks,
            setter: { $0.note = canonical; $0.noteID = canonical.id.uuidString }
        )
    }

    // MARK: - Deduplicate All Models

    /// Deduplicates all model types in the database.
    /// CloudKit sync can create duplicate records with the same ID during merge conflicts.
    /// This removes all duplicates, keeping one instance of each ID.
    /// Returns a dictionary of model type names to the number of duplicates removed.
    @discardableResult
    static func deduplicateAllModels(using context: ModelContext) -> [String: Int] {
        var results: [String: Int] = [:]

        // Core models (most likely to have user-visible duplicates)
        results["Student"] = deduplicateStudentsStrong(using: context)
        results["Lesson"] = deduplicateLessonsStrong(using: context)
        // Legacy model removed -- fully migrated to LessonAssignment
        results["LessonAssignment"] = deduplicate(LessonAssignment.self, using: context)
        results["LessonPresentation"] = deduplicateLessonPresentationsStrong(using: context)

        // Work-related models
        results["WorkModel"] = deduplicateWorkModelsStrong(using: context)
        results["WorkCheckIn"] = deduplicate(WorkCheckIn.self, using: context)
        results["WorkCompletionRecord"] = deduplicate(WorkCompletionRecord.self, using: context)
        // WorkPlanItem removed in Phase 6 - migrated to WorkCheckIn
        results["WorkParticipantEntity"] = deduplicate(WorkParticipantEntity.self, using: context)
        results["WorkStep"] = deduplicate(WorkStep.self, using: context)

        // Project models
        results["Project"] = deduplicate(Project.self, using: context)
        results["ProjectRole"] = deduplicate(ProjectRole.self, using: context)
        results["ProjectSession"] = deduplicate(ProjectSession.self, using: context)
        results["ProjectAssignmentTemplate"] = deduplicate(ProjectAssignmentTemplate.self, using: context)
        results["ProjectTemplateWeek"] = deduplicate(ProjectTemplateWeek.self, using: context)
        results["ProjectWeekRoleAssignment"] = deduplicate(ProjectWeekRoleAssignment.self, using: context)

        // Track models
        results["Track"] = deduplicate(Track.self, using: context)
        results["TrackStep"] = deduplicate(TrackStep.self, using: context)
        results["GroupTrack"] = deduplicate(GroupTrack.self, using: context)
        results["StudentTrackEnrollment"] = deduplicate(StudentTrackEnrollment.self, using: context)

        // Notes and documents
        results["Note"] = deduplicateNotesStrong(using: context)
        results["NoteTemplate"] = deduplicate(NoteTemplate.self, using: context)
        results["NoteStudentLink"] = deduplicate(NoteStudentLink.self, using: context)
        results["Document"] = deduplicate(Document.self, using: context)

        // Attendance and calendar
        results["AttendanceRecord"] = deduplicate(AttendanceRecord.self, using: context)
        results["StudentMeeting"] = deduplicate(StudentMeeting.self, using: context)
        results["MeetingTemplate"] = deduplicate(MeetingTemplate.self, using: context)
        results["CalendarEvent"] = deduplicate(CalendarEvent.self, using: context)
        results["NonSchoolDay"] = deduplicate(NonSchoolDay.self, using: context)
        results["SchoolDayOverride"] = deduplicate(SchoolDayOverride.self, using: context)

        // Community models
        results["CommunityTopic"] = deduplicate(CommunityTopic.self, using: context)
        results["ProposedSolution"] = deduplicate(ProposedSolution.self, using: context)
        results["CommunityAttachment"] = deduplicate(CommunityAttachment.self, using: context)

        // Other models
        results["Reminder"] = deduplicate(Reminder.self, using: context)

        // Filter out zero counts for cleaner output
        return results.filter { $0.value > 0 }
    }
}
// swiftlint:enable cyclomatic_complexity
