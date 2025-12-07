import Foundation
import SwiftData

enum DataMigrations {
    /// Normalize all existing StudentLesson.givenAt values to start-of-day (strip time) once.
    /// Idempotent: guarded by a UserDefaults flag and only updates rows where time != start of day.
    static func normalizeGivenAtToDateOnlyIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.givenAtDateOnly.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        let calendar = Calendar.current
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
        let calendar = Calendar.current
        do {
            var changed = 0
            // WorkModel
            let works = try context.fetch(FetchDescriptor<WorkModel>())
            for w in works {
                let createdNorm = calendar.startOfDay(for: w.createdAt)
                if w.createdAt != createdNorm { w.createdAt = createdNorm; changed += 1 }
                if let c = w.completedAt {
                    let norm = calendar.startOfDay(for: c)
                    if c != norm { w.completedAt = norm; changed += 1 }
                }
            }
            // WorkParticipantEntity
            let participants = try context.fetch(FetchDescriptor<WorkParticipantEntity>())
            for p in participants {
                if let c = p.completedAt {
                    let norm = calendar.startOfDay(for: c)
                    if c != norm { p.completedAt = norm; changed += 1 }
                }
            }
            // WorkCompletionRecord
            let completions = try context.fetch(FetchDescriptor<WorkCompletionRecord>())
            for rc in completions {
                let norm = calendar.startOfDay(for: rc.completedAt)
                if rc.completedAt != norm { rc.completedAt = norm; changed += 1 }
            }
            // WorkCheckIn
            let checkIns = try context.fetch(FetchDescriptor<WorkCheckIn>())
            for ci in checkIns {
                let norm = calendar.startOfDay(for: ci.date)
                if ci.date != norm { ci.date = norm; changed += 1 }
            }
            if changed > 0 { try? context.save() }
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            // If fetch fails, do not set the flag so we can retry later.
        }
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
            let sortedIDs = sl.studentIDs.sorted { $0.uuidString < $1.uuidString }
            let key = sl.lessonID.uuidString + "|" + sortedIDs.map { $0.uuidString }.joined(separator: ",")
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
            if canonical.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let firstNote = duplicates.map({ $0.notes }).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    canonical.notes = firstNote
                }
            }
            if canonical.followUpWork.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let firstFU = duplicates.map({ $0.followUpWork }).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    canonical.followUpWork = firstFU
                }
            }

            // Delete duplicates
            for d in duplicates { context.delete(d) }
            changed = true
        }

        if changed { try? context.save() }
    }

    /// Backfill missing work participants from studentIDs and delete truly empty works once.
    /// - If a WorkModel has no studentIDs and no participants, delete it.
    /// - If a WorkModel has studentIDs but no participants, create participants for each studentID.
    ///   If the work has a global completedAt, apply it to each participant and backfill completion records.
    static func backfillParticipantsAndDeleteEmptyWorksIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.workParticipantsBackfill.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        do {
            let works = try context.fetch(FetchDescriptor<WorkModel>())
            var changed = 0
            for w in works {
                if w.studentIDs.isEmpty && w.participants.isEmpty {
                    context.delete(w)
                    changed += 1
                    continue
                }
                if !w.studentIDs.isEmpty && w.participants.isEmpty {
                    // Create participants from studentIDs
                    w.ensureParticipantsFromStudentIDs()
                    // If the work has a global completion date, propagate to each participant
                    if let completed = w.completedAt {
                        for i in 0..<w.participants.count {
                            w.participants[i].completedAt = completed
                        }
                        // Backfill durable completion records for history
                        try? WorkCompletionBackfill.backfill(for: w.id, participants: w.participants, in: context)
                    }
                    changed += 1
                }
            }
            if changed > 0 { try? context.save() }
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            // If fetch fails, do not set the flag so we can retry later.
        }
    }
}
