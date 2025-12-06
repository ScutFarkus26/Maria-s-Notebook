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
}
