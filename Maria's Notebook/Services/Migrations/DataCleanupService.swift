import Foundation
import SwiftData
import OSLog

// MARK: - Data Cleanup Service

/// Service responsible for cleaning up orphaned data and maintaining referential integrity.
/// Handles cleanup of orphaned student IDs, duplicate records, and other data integrity issues.
enum DataCleanupService {
    private static let logger = Logger.migration

    // MARK: - Orphaned Student ID Cleanup

    /// Cleans orphaned student IDs from StudentLesson records.
    /// Removes student IDs that no longer exist in the database to maintain referential integrity
    /// when using manual ID management instead of SwiftData relationships.
    /// Safe to call repeatedly - it's idempotent and only removes non-existent IDs.
    static func cleanOrphanedStudentIDs(using context: ModelContext) async {
        // Fetch all students to build valid ID set
        let studentFetch = FetchDescriptor<Student>()
        let allStudents = context.safeFetch(studentFetch)
        
        // Guard against empty student list - if fetch failed, bail out to prevent mass deletion
        guard !allStudents.isEmpty else {
            logger.warning("cleanOrphanedStudentIDs: No students found - skipping cleanup to prevent data loss")
            return
        }
        
        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })

        // Fetch all StudentLessons
        let lessonFetch = FetchDescriptor<StudentLesson>()
        let allLessons = context.safeFetch(lessonFetch)

        var cleaned = 0
        for (index, sl) in allLessons.enumerated() {
            if index % 100 == 0 { await Task.yield() }

            let originalIDs = sl.studentIDs
            let cleanedIDs = originalIDs.filter { validStudentIDs.contains($0) }

            if cleanedIDs.count != originalIDs.count {
                sl.studentIDs = cleanedIDs
                // Also update the transient relationship array
                sl.students = sl.students.filter { student in
                    validStudentIDs.contains(student.cloudKitKey)
                }
                cleaned += 1
            }
        }

        if cleaned > 0 {
            context.safeSave()
        }
    }

    /// Cleans orphaned student IDs from WorkModel records.
    /// Removes student IDs that no longer exist in the database to maintain referential integrity
    /// when using manual ID management instead of SwiftData relationships.
    /// Safe to call repeatedly - it's idempotent and only removes non-existent IDs.
    static func cleanOrphanedWorkStudentIDs(using context: ModelContext) async {
        // Fetch all students to build valid ID set
        let studentFetch = FetchDescriptor<Student>()
        let allStudents = context.safeFetch(studentFetch)
        
        // Guard against empty student list - if fetch failed, bail out to prevent mass deletion
        guard !allStudents.isEmpty else {
            logger.warning("cleanOrphanedWorkStudentIDs: No students found - skipping cleanup to prevent data loss")
            return
        }
        
        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })

        // Fetch all WorkModels
        let workFetch = FetchDescriptor<WorkModel>()
        let allWorks = context.safeFetch(workFetch)

        var cleaned = 0
        for (index, work) in allWorks.enumerated() {
            // Yield every 100 iterations to prevent blocking
            if index % 100 == 0 { await Task.yield() }

            var modified = false

            // Check work.studentID - if not empty and not in valid set, clear it
            if !work.studentID.isEmpty && !validStudentIDs.contains(work.studentID) {
                work.studentID = ""
                modified = true
            }

            // Check work.participants - remove any with orphaned studentIDs
            if let participants = work.participants, !participants.isEmpty {
                let validParticipants = participants.filter { participant in
                    validStudentIDs.contains(participant.studentID)
                }

                if validParticipants.count != participants.count {
                    work.participants = validParticipants.isEmpty ? nil : validParticipants
                    // Delete orphaned participants from context
                    for participant in participants {
                        if !validStudentIDs.contains(participant.studentID) {
                            context.delete(participant)
                        }
                    }
                    modified = true
                }
            }

            if modified {
                cleaned += 1
            }
        }

        if cleaned > 0 {
            context.safeSave()
        }
    }

    /// Deduplicate unscheduled, unpresented StudentLesson records that refer to the same lesson and identical student set.
    /// Keeps the earliest `createdAt` as canonical, merges flags, and deletes the rest.
    static func deduplicateUnpresentedStudentLessons(using context: ModelContext) {
        // Fetch all candidate lessons (unscheduled and not given)
        let descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.scheduledFor == nil && $0.givenAt == nil })
        let candidates = context.safeFetch(descriptor)
        guard !candidates.isEmpty else { return }

        // Group by (lessonID + sorted studentIDs)
        let groups = candidates.grouped { sl -> String in
            let sortedIDs = sl.studentIDs.sorted()
            return sl.lessonID + "|" + sortedIDs.joined(separator: ",")
        }

        var changed = false
        for (_, group) in groups {
            guard group.count > 1 else { continue }
            // Choose canonical: earliest createdAt, with stable tiebreaker by ID
            guard let canonical = group.sorted(by: { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }).first else { continue }
            let duplicates = group.filter { $0.id != canonical.id }

            // Merge flags conservatively
            if duplicates.contains(where: { $0.needsPractice }) {
                canonical.needsPractice = true
            }
            if duplicates.contains(where: { $0.needsAnotherPresentation }) {
                canonical.needsAnotherPresentation = true
            }
            // Prefer non-empty notes/followUpWork if canonical empty
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

            // Delete duplicates
            for d in duplicates { context.delete(d) }
            changed = true
        }

        if changed { context.safeSave() }
    }

    // MARK: - Note Cleanup

    /// Repair scope for notes that were incorrectly set to .all due to UI bugs.
    /// Specifically targets Attendance, WorkCompletion, and StudentMeeting notes.
    static func repairScopeForContextualNotes(using context: ModelContext) async {
        let flagKey = "Repair.noteScopes.v1"
        MigrationFlag.runIfNeeded(key: flagKey) {
            let notes = context.safeFetch(FetchDescriptor<Note>())
            var changed = 0

            for note in notes {
                var targetStudentID: UUID? = nil

                if let rec = note.attendanceRecord, let uuid = UUID(uuidString: rec.studentID) {
                    targetStudentID = uuid
                } else if let rec = note.workCompletionRecord, let uuid = UUID(uuidString: rec.studentID) {
                    targetStudentID = uuid
                } else if let meeting = note.studentMeeting, let uuid = UUID(uuidString: meeting.studentID) {
                    targetStudentID = uuid
                }

                if let targetID = targetStudentID {
                    var needsFix = true
                    if case .student(let currentID) = note.scope {
                        if currentID == targetID { needsFix = false }
                    }
                    if needsFix {
                        note.scope = .student(targetID)
                        changed += 1
                    }
                }
            }

            if changed > 0 {
                context.safeSave()
            }
        }
    }

    /// Clean up orphaned note images that are no longer referenced by any Note.
    /// This should be run after note deletions to reclaim disk space.
    static func cleanupOrphanedNoteImages(using context: ModelContext) {
        do {
            let photosDir = try PhotoStorageService.photosDirectory()
            let fm = FileManager.default

            // Get all files in the Note Photos directory
            let files = try fm.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil)
            let imageFilenames = Set(files.map { $0.lastPathComponent })

            // Get all image paths referenced by notes
            let notesFetch = FetchDescriptor<Note>()
            let notes = context.safeFetch(notesFetch)
            let referencedPaths = Set(notes.compactMap { $0.imagePath })

            // Find orphaned files
            let orphanedFiles = imageFilenames.subtracting(referencedPaths)

            for filename in orphanedFiles {
                do {
                    try PhotoStorageService.deleteImage(filename: filename)
                } catch {
                    logger.warning("Failed to delete orphaned image \(filename, privacy: .public): \(error.localizedDescription)")
                }
            }
        } catch {
            logger.warning("Failed to cleanup orphaned images: \(error.localizedDescription)")
        }
    }

    /// Create NoteStudentLink records for existing notes with multi-student scope.
    /// This enables efficient database-level queries instead of in-memory filtering.
    static func createNoteStudentLinksForExistingNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { note in
                note.scopeIsAll == false && note.searchIndexStudentID == nil
            }
        )
        let notes = context.safeFetch(fetch)

        var createdCount = 0

        for note in notes {
            // Skip if links already exist
            guard (note.studentLinks ?? []).isEmpty else { continue }

            // Sync the student links based on current scope
            note.syncStudentLinks(in: context)

            if !(note.studentLinks ?? []).isEmpty {
                createdCount += 1
            }
        }

        if createdCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - Denormalized Field Repair

    /// Repairs denormalized scheduledForDay fields to match scheduledFor.
    /// This ensures data integrity when scheduledForDay gets out of sync with scheduledFor
    /// (e.g., during bulk imports or when didSet doesn't fire during initialization).
    /// Safe to call repeatedly - it's idempotent and only fixes mismatched records.
    static func repairDenormalizedScheduledForDay(using context: ModelContext) async {
        let fetch = FetchDescriptor<StudentLesson>()
        let lessons = context.safeFetch(fetch)
        var repaired = 0

        for (index, sl) in lessons.enumerated() {
            if index % 100 == 0 { await Task.yield() }

            let correct = sl.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
            if sl.scheduledForDay != correct {
                sl.scheduledForDay = correct
                repaired += 1
            }
        }

        if repaired > 0 {
            context.safeSave()
        }
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
        for item in all {
            if !seen.insert(item.id).inserted {
                hasDuplicates = true
                break
            }
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

    private static func mergeRelationship<T: Identifiable>(
        from source: [T]?,
        to destination: inout [T]?,
        setter: (T) -> Void
    ) where T.ID == UUID {
        guard let sourceItems = source, !sourceItems.isEmpty else { return }
        if destination == nil { destination = [] }
        var existingIDs = Set((destination ?? []).map { $0.id })
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
        if canonical.orderInGroup == 0 && duplicate.orderInGroup != 0 { canonical.orderInGroup = duplicate.orderInGroup }
        if canonical.sortIndex == 0 && duplicate.sortIndex != 0 { canonical.sortIndex = duplicate.sortIndex }
        if canonical.pagesFileBookmark == nil { canonical.pagesFileBookmark = duplicate.pagesFileBookmark }
        if canonical.pagesFileRelativePath == nil { canonical.pagesFileRelativePath = duplicate.pagesFileRelativePath }
        if canonical.personalKindRaw == nil { canonical.personalKindRaw = duplicate.personalKindRaw }
        if canonical.defaultWorkKindRaw == nil { canonical.defaultWorkKindRaw = duplicate.defaultWorkKindRaw }

        mergeRelationship(from: duplicate.notes, to: &canonical.notes, setter: { $0.lesson = canonical })
        mergeRelationship(from: duplicate.studentLessons, to: &canonical.studentLessons, setter: { $0.lesson = canonical })
        mergeRelationship(from: duplicate.lessonAssignments, to: &canonical.lessonAssignments, setter: { $0.lesson = canonical })
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
        mergeRelationship(from: duplicate.checkIns, to: &canonical.checkIns, setter: { $0.work = canonical; $0.workID = canonical.id.uuidString })
        mergeRelationship(from: duplicate.steps, to: &canonical.steps, setter: { $0.work = canonical })
        mergeRelationship(from: duplicate.unifiedNotes, to: &canonical.unifiedNotes, setter: { $0.work = canonical })
    }

    private static func mergeNote(canonical: Note, duplicate: Note) {
        if canonical.body.isEmpty { canonical.body = duplicate.body }
        if !canonical.isPinned && duplicate.isPinned { canonical.isPinned = true }
        if !canonical.includeInReport && duplicate.includeInReport { canonical.includeInReport = true }
        if canonical.imagePath == nil || canonical.imagePath?.isEmpty == true { canonical.imagePath = duplicate.imagePath }
        if canonical.reportedBy == nil { canonical.reportedBy = duplicate.reportedBy }
        if canonical.reporterName == nil { canonical.reporterName = duplicate.reporterName }

        // Merge relationships (parent entities)
        if canonical.lesson == nil { canonical.lesson = duplicate.lesson }
        if canonical.work == nil { canonical.work = duplicate.work }
        if canonical.studentLesson == nil { canonical.studentLesson = duplicate.studentLesson }
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
        if canonical.studentTrackEnrollment == nil { canonical.studentTrackEnrollment = duplicate.studentTrackEnrollment }

        mergeRelationship(from: duplicate.studentLinks, to: &canonical.studentLinks, setter: { $0.note = canonical; $0.noteID = canonical.id.uuidString })
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
        results["StudentLesson"] = deduplicate(StudentLesson.self, using: context)
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

    // MARK: - Run All Cleanup Operations

    /// Runs all data cleanup operations in sequence.
    /// Safe to call repeatedly - each operation is idempotent.
    static func runAllCleanupOperations(using context: ModelContext) async {
        // Run comprehensive deduplication first since other cleanups depend on valid data
        _ = deduplicateAllModels(using: context)
        await cleanOrphanedStudentIDs(using: context)
        await cleanOrphanedWorkStudentIDs(using: context)
        deduplicateUnpresentedStudentLessons(using: context)
        await repairScopeForContextualNotes(using: context)
        await repairDenormalizedScheduledForDay(using: context)
    }
}
