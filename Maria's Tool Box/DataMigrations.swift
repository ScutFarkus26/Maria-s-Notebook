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
    
    /// Backfill or repair `scheduledForDay` for all StudentLesson rows from `scheduledFor`.
    /// Idempotent: guarded by a UserDefaults flag and only updates rows where the value is mismatched.
    static func repairScheduledForDayIfNeeded(using context: ModelContext, calendar: Calendar = AppCalendar.shared) {
        let flagKey = "Migration.repairScheduledForDay.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        do {
            let fetch = FetchDescriptor<StudentLesson>()
            let lessons = try context.fetch(fetch)
            var changed = 0
            for sl in lessons {
                let expected: Date = {
                    if let dt = sl.scheduledFor {
                        return calendar.startOfDay(for: dt)
                    } else {
                        return Date.distantPast
                    }
                }()
                if sl.scheduledForDay != expected {
                    sl.scheduledForDay = expected
                    changed += 1
                }
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
    
    /// Backfill Work participants from legacy studentIDs and delete empty Work items if needed.
    /// Idempotent and safe to call multiple times.
    static func backfillParticipantsAndDeleteEmptyWorksIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.workParticipantsBackfillAndPrune.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        do {
            let works = try context.fetch(FetchDescriptor<WorkModel>())
            var changed = false
            for w in works {
                // If there are no participants but legacy studentIDs were used historically,
                // reconstruct participants from any linked StudentLesson.
                if w.participants.isEmpty, let slID = w.studentLessonID {
                    if let sl = try? context.fetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == slID })).first {
                        let parts = sl.studentIDs.map { sid in WorkParticipantEntity(studentID: sid, completedAt: nil, work: w) }
                        if !parts.isEmpty {
                            w.participants = parts
                            changed = true
                        }
                    }
                }
            }
            // Delete any works that still have no participants and are not completed
            // (legacy artifacts that would clutter the UI)
            for w in works where w.participants.isEmpty {
                context.delete(w)
                changed = true
            }
            if changed { try context.save() }
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            // Best-effort; do not set the flag so we can retry later
        }
    }
}

