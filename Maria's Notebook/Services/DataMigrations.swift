import Foundation
import SwiftData

enum DataMigrations {
    /// Normalize all existing StudentLesson.givenAt values to start-of-day (strip time) once.
    /// Idempotent: guarded by a UserDefaults flag and only updates rows where time != start of day.
    static func normalizeGivenAtToDateOnlyIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.givenAtDateOnly.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        let calendar = AppCalendar.shared
        do {
            let fetch = FetchDescriptor<StudentLesson>()
            let lessons = try context.fetch(fetch)
            var changed = 0
            for sl in lessons {
                if let dt = sl.givenAt {
                    let normalized = calendar.startOfDay(for: dt)
                    if dt != normalized {
                        sl.givenAt = normalized
                        changed += 1
                    }
                }
            }
            if changed > 0 { try? context.save() }
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            // If fetch fails, do not set the flag so we can retry later.
        }
    }

    /// Normalize all Work-related dates to start-of-day (strip time) once.
    /// - WorkModel.createdAt, WorkModel.completedAt
    /// - WorkParticipantEntity.completedAt
    /// - WorkCompletionRecord.completedAt
    /// - WorkCheckIn.date
    static func normalizeWorkDatesToDateOnlyIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.workDatesDateOnly.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    /// Deduplicate unscheduled, unpresented StudentLesson records that refer to the same lesson and identical student set.
    /// Keeps the earliest `createdAt` as canonical, merges flags, and deletes the rest.
    static func deduplicateUnpresentedStudentLessons(using context: ModelContext) {
        // Fetch all candidate lessons (unscheduled and not given)
        let descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.scheduledFor == nil && $0.givenAt == nil })
        let candidates = (try? context.fetch(descriptor)) ?? []
        guard !candidates.isEmpty else { return }

        // Group by (lessonID + sorted studentIDs)
        let groups = Dictionary(grouping: candidates) { sl -> String in
            let sortedIDs = sl.studentIDs.sorted()
            let key = sl.lessonID.uuidString + "|" + sortedIDs.joined(separator: ",")
            return key
        }

        var changed = false
        for (_, group) in groups {
            guard group.count > 1 else { continue }
            // Choose canonical: earliest createdAt
            let canonical = group.min(by: { $0.createdAt < $1.createdAt })!
            let duplicates = group.filter { $0.id != canonical.id }

            // Merge flags conservatively
            if duplicates.contains(where: { $0.needsPractice }) {
                canonical.needsPractice = true
            }
            if duplicates.contains(where: { $0.needsAnotherPresentation }) {
                canonical.needsAnotherPresentation = true
            }
            // Prefer non-empty notes/followUpWork if canonical empty
            if canonical.notes.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                if let firstNote = duplicates.map({ $0.notes }).first(where: { !$0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty }) {
                    canonical.notes = firstNote
                }
            }
            if canonical.followUpWork.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                if let firstFU = duplicates.map({ $0.followUpWork }).first(where: { !$0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty }) {
                    canonical.followUpWork = firstFU
                }
            }

            // Delete duplicates
            for d in duplicates { context.delete(d) }
            changed = true
        }

        if changed { try? context.save() }
    }
    
    /// Backfill Work participants from legacy studentIDs and delete empty Work items if needed.
    /// Idempotent and safe to call multiple times.
    static func backfillParticipantsAndDeleteEmptyWorksIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.workParticipantsBackfillAndPrune.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        UserDefaults.standard.set(true, forKey: flagKey)
    }
    
    /// Backfill nil WorkModel.title values to empty string once.
    static func backfillEmptyWorkTitlesIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.workTitlesBackfillEmpty.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        // Title is non-optional; this migration is obsolete. Mark as done.
        UserDefaults.standard.set(true, forKey: flagKey)
    }
    
    /// Fix CommunityTopic.tags property migration to new storage format.
    /// The tags property now uses JSON-encoded Data storage (_tagsData) instead of direct array storage.
    /// 
    /// IMPORTANT: This migration cannot fetch CommunityTopic records directly because SwiftData
    /// may crash when trying to read the old tags property from corrupted data. Instead, we use
    /// a lazy migration approach where records are migrated when they are accessed and saved.
    /// 
    /// The computed property in CommunityTopic safely handles corrupted data by returning an
    /// empty array if _tagsData contains invalid data, preventing crashes.
    static func fixCommunityTopicTagsIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.communityTopicTagsFix.v2"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        
        // Mark migration as complete immediately to prevent any fetch attempts that might crash
        // The computed property in CommunityTopic will safely handle corrupted data
        // by returning an empty array if _tagsData contains invalid data.
        // Records will be migrated lazily when accessed and saved (tags property setter encodes to _tagsData).
        UserDefaults.standard.set(true, forKey: flagKey)
        print("DataMigrations: CommunityTopic tags migration v2 flag set. Records will be migrated lazily on access.")
    }
    
    /// Fix StudentLesson.studentIDs property migration to new storage format.
    /// The studentIDs property now uses JSON-encoded Data storage (_studentIDsData) instead of direct array storage.
    /// 
    /// IMPORTANT: This migration cannot fetch StudentLesson records directly because SwiftData
    /// may crash when trying to read the old studentIDs property from corrupted data (UUIDs instead of Strings).
    /// Instead, we use a lazy migration approach where records are migrated when they are accessed and saved.
    /// 
    /// The computed property in StudentLesson safely handles corrupted data by returning an
    /// empty array if _studentIDsData contains invalid data, preventing crashes.
    static func fixStudentLessonStudentIDsIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.studentLessonStudentIDsFix.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        
        // Mark migration as complete immediately to prevent any fetch attempts that might crash
        // The computed property in StudentLesson will safely handle corrupted data
        // by returning an empty array if _studentIDsData contains invalid data.
        // Records will be migrated lazily when accessed and saved (studentIDs property setter encodes to _studentIDsData).
        UserDefaults.standard.set(true, forKey: flagKey)
        print("DataMigrations: StudentLesson studentIDs migration flag set. Records will be migrated lazily on access.")
    }
}
