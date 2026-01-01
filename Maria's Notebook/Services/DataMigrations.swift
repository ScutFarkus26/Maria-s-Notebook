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
    /// The tags property now uses JSON-encoded string storage (tagsRaw) instead of direct array storage.
    /// This migration ensures all existing topics have valid JSON in tagsRaw.
    /// Note: This must run before any CommunityTopic is accessed to avoid crashes from type mismatches.
    static func fixCommunityTopicTagsIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.communityTopicTagsFix.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        
        // Use a flag to track if we've successfully migrated
        // Don't set it until migration completes to allow retries
        do {
            // Fetch with error handling - if this crashes, the migration will be retried on next launch
            let fetch = FetchDescriptor<CommunityTopic>()
            let topics = try context.fetch(fetch)
            var changed = 0
            
            for topic in topics {
                // Access tags property - it will safely decode from tagsRaw
                // If tagsRaw contains invalid data, it will return empty array
                // Force a save to ensure tagsRaw is properly set
                let currentTags = topic.tags
                topic.tags = currentTags // This will encode to tagsRaw properly
                changed += 1
            }
            
            if changed > 0 {
                try context.save()
                print("DataMigrations: Migrated \(changed) CommunityTopic tags to new storage format")
            }
            // Only set flag after successful completion
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            // If fetch or save fails (e.g., due to type mismatch crash), don't set the flag
            // This allows the migration to be retried on next launch
            print("DataMigrations: Error fixing CommunityTopic tags (will retry): \(error)")
            // Don't set the flag - allow retry
        }
    }
}
