import Foundation
import SwiftData

// MARK: - Data Cleanup Service

/// Service responsible for cleaning up orphaned data and maintaining referential integrity.
/// Handles cleanup of orphaned student IDs, duplicate records, and other data integrity issues.
enum DataCleanupService {

    // MARK: - Orphaned Student ID Cleanup

    /// Cleans orphaned student IDs from StudentLesson records.
    /// Removes student IDs that no longer exist in the database to maintain referential integrity
    /// when using manual ID management instead of SwiftData relationships.
    /// Safe to call repeatedly - it's idempotent and only removes non-existent IDs.
    static func cleanOrphanedStudentIDs(using context: ModelContext) async {
        // Fetch all students to build valid ID set
        let studentFetch = FetchDescriptor<Student>()
        let allStudents = context.safeFetch(studentFetch)
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
                    validStudentIDs.contains(student.id.uuidString)
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

    // MARK: - Deduplication

    /// Removes duplicate Student records that have the same UUID.
    /// This can happen when CloudKit sync creates duplicates during merge conflicts.
    /// Keeps the most recently modified instance (by modifiedAt) and deletes the duplicates.
    /// Returns the number of duplicate students removed.
    @discardableResult
    static func deduplicateStudents(using context: ModelContext) -> Int {
        let fetch = FetchDescriptor<Student>()
        let allStudents = context.safeFetch(fetch)

        // Group by ID
        var studentsByID: [UUID: [Student]] = [:]
        for student in allStudents {
            studentsByID[student.id, default: []].append(student)
        }

        var deletedCount = 0

        // For each group with duplicates, keep the most recently modified and delete the rest
        for (_, students) in studentsByID where students.count > 1 {
            // Sort by modifiedAt descending - keep the most recently modified
            let sorted = students.sorted { $0.modifiedAt > $1.modifiedAt }
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            context.safeSave()
        }

        return deletedCount
    }

    /// Removes duplicate Project records that have the same UUID.
    /// This can happen when CloudKit sync creates duplicates during merge conflicts.
    /// Keeps the most recently modified instance (by modifiedAt) and deletes the duplicates.
    /// Returns the number of duplicate projects removed.
    @discardableResult
    static func deduplicateProjects(using context: ModelContext) -> Int {
        let fetch = FetchDescriptor<Project>()
        let allProjects = context.safeFetch(fetch)

        // Group by ID
        var projectsByID: [UUID: [Project]] = [:]
        for project in allProjects {
            projectsByID[project.id, default: []].append(project)
        }

        var deletedCount = 0

        // For each group with duplicates, keep the most recently modified and delete the rest
        for (_, projects) in projectsByID where projects.count > 1 {
            // Sort by modifiedAt descending - keep the most recently modified
            let sorted = projects.sorted { $0.modifiedAt > $1.modifiedAt }
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            context.safeSave()
        }

        return deletedCount
    }

    /// Removes duplicate ProjectRole records that have the same UUID.
    /// This can happen when CloudKit sync creates duplicates during merge conflicts.
    /// Keeps one instance of each role and deletes the duplicates.
    /// Returns the number of duplicate roles removed.
    @discardableResult
    static func deduplicateProjectRoles(using context: ModelContext) -> Int {
        let fetch = FetchDescriptor<ProjectRole>()
        let allRoles = context.safeFetch(fetch)

        // Group by ID
        var rolesByID: [UUID: [ProjectRole]] = [:]
        for role in allRoles {
            rolesByID[role.id, default: []].append(role)
        }

        var deletedCount = 0

        // For each group with duplicates, keep one and delete the rest
        for (_, roles) in rolesByID where roles.count > 1 {
            // Keep the first one (arbitrary, but consistent), delete the rest
            for duplicate in roles.dropFirst() {
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            context.safeSave()
        }

        return deletedCount
    }

    /// Removes duplicate Lesson records that have the same UUID.
    /// This can happen when CloudKit sync creates duplicates during merge conflicts.
    /// Keeps the first instance (arbitrary, but consistent) and deletes the duplicates.
    /// Returns the number of duplicate lessons removed.
    @discardableResult
    static func deduplicateLessons(using context: ModelContext) -> Int {
        let fetch = FetchDescriptor<Lesson>()
        let allLessons = context.safeFetch(fetch)

        // Group by ID
        var lessonsByID: [UUID: [Lesson]] = [:]
        for lesson in allLessons {
            lessonsByID[lesson.id, default: []].append(lesson)
        }

        var deletedCount = 0

        // For each group with duplicates, keep one and delete the rest
        for (_, lessons) in lessonsByID where lessons.count > 1 {
            // Keep the first one (arbitrary, but consistent), delete the rest
            for duplicate in lessons.dropFirst() {
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            context.safeSave()
        }

        return deletedCount
    }

    /// Removes duplicate AttendanceRecord records that have the same UUID.
    /// This can happen when CloudKit sync creates duplicates during merge conflicts.
    /// Keeps the first instance and deletes the duplicates.
    /// Returns the number of duplicate records removed.
    @discardableResult
    static func deduplicateAttendanceRecords(using context: ModelContext) -> Int {
        let fetch = FetchDescriptor<AttendanceRecord>()
        let allRecords = context.safeFetch(fetch)

        // Group by ID
        var recordsByID: [UUID: [AttendanceRecord]] = [:]
        for record in allRecords {
            recordsByID[record.id, default: []].append(record)
        }

        var deletedCount = 0

        // For each group with duplicates, keep one and delete the rest
        for (_, records) in recordsByID where records.count > 1 {
            // Keep the first one (arbitrary, but consistent), delete the rest
            for duplicate in records.dropFirst() {
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            context.safeSave()
        }

        return deletedCount
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
            // Choose canonical: earliest createdAt
            guard let canonical = group.min(by: { $0.createdAt < $1.createdAt }) else { continue }
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
        await MigrationFlag.runIfNeeded(key: flagKey) {
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
                    let shouldFix = await Task { @MainActor in
                        var needsFix = true
                        if case .student(let currentID) = note.scope {
                            if currentID == targetID { needsFix = false }
                        }
                        if needsFix {
                            note.scope = .student(targetID)
                        }
                        return needsFix
                    }.value

                    if shouldFix {
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
    @MainActor
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
                try? PhotoStorageService.deleteImage(filename: filename)
            }
        } catch {
            // Failed to cleanup orphaned images - continue silently
        }
    }

    /// Create NoteStudentLink records for existing notes with multi-student scope.
    /// This enables efficient database-level queries instead of in-memory filtering.
    @MainActor
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
    private static func deduplicate<T: PersistentModel & Identifiable>(
        _ type: T.Type,
        using context: ModelContext
    ) -> Int where T.ID == UUID {
        let fetch = FetchDescriptor<T>()
        // Fetch raw without deduplication to find actual duplicates in the database
        let all = (try? context.fetch(fetch)) ?? []

        // Group by ID
        var byID: [UUID: [T]] = [:]
        for item in all {
            byID[item.id, default: []].append(item)
        }

        var deletedCount = 0

        // For each group with duplicates, keep the first and delete the rest
        for (_, items) in byID where items.count > 1 {
            for duplicate in items.dropFirst() {
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            context.safeSave()
        }

        return deletedCount
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
        results["Student"] = deduplicate(Student.self, using: context)
        results["Lesson"] = deduplicate(Lesson.self, using: context)
        results["StudentLesson"] = deduplicate(StudentLesson.self, using: context)
        results["LessonAssignment"] = deduplicate(LessonAssignment.self, using: context)
        results["LessonPresentation"] = deduplicate(LessonPresentation.self, using: context)

        // Work-related models
        results["WorkModel"] = deduplicate(WorkModel.self, using: context)
        results["WorkCheckIn"] = deduplicate(WorkCheckIn.self, using: context)
        results["WorkCompletionRecord"] = deduplicate(WorkCompletionRecord.self, using: context)
        results["WorkPlanItem"] = deduplicate(WorkPlanItem.self, using: context)
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
        results["Note"] = deduplicate(Note.self, using: context)
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
        results["AlbumGroupOrder"] = deduplicate(AlbumGroupOrder.self, using: context)
        results["AlbumGroupUIState"] = deduplicate(AlbumGroupUIState.self, using: context)

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
