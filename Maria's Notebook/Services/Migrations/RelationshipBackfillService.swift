import Foundation
import SwiftData

// MARK: - Relationship Backfill Service

/// Service responsible for backfilling relationships between entities.
/// Handles linking StudentLessons to Lessons, Students, and other related entities.
enum RelationshipBackfillService {

    // MARK: - StudentLesson Relationships

    /// Backfill StudentLesson relationships from legacy studentIDs and lessonID strings.
    /// One-time migration that ensures relationship arrays are populated from denormalized ID fields.
    /// Idempotent: guarded by a UserDefaults flag.
    /// Yields periodically to allow UI updates during large migrations.
    static func backfillRelationshipsIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.relationships.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            // OPTIMIZATION: Fetch all data once (these are relatively small lookups)
            let sls = context.safeFetch(FetchDescriptor<StudentLesson>())
            let students = context.safeFetch(FetchDescriptor<Student>())
            let lessons = context.safeFetch(FetchDescriptor<Lesson>())
            let studentsByID = students.toDictionary(by: \.id)
            let lessonsByID = lessons.toDictionary(by: \.id)

            // OPTIMIZATION: Process in batches and save periodically to avoid memory pressure
            let batchSize = BatchingConstants.defaultBatchSize
            var changed = false
            var processed = 0

            for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                // Yield periodically to prevent blocking UI
                if batchStart % 500 == 0 {
                    await Task.yield()
                }

                let batchEnd = min(batchStart + batchSize, sls.count)
                let batch = Array(sls[batchStart..<batchEnd])

                for sl in batch {
                    // CloudKit compatibility: Convert String lessonID to UUID for lookup
                    guard let lessonIDUUID = UUID(uuidString: sl.lessonID) else { continue }
                    let targetLesson = lessonsByID[lessonIDUUID]
                    let targetStudents: [Student] = sl.studentIDs.compactMap { idString in
                        guard let id = UUID(uuidString: idString) else { return nil }
                        return studentsByID[id]
                    }
                    if sl.lesson?.id != targetLesson?.id { sl.lesson = targetLesson; changed = true }
                    let currentIDs = Set(sl.students.map { $0.id })
                    let targetIDs = Set(targetStudents.map { $0.id })
                    if currentIDs != targetIDs {
                        sl.students = targetStudents
                        changed = true
                    }
                    if changed {
                        sl.syncSnapshotsFromRelationships()
                    }
                }

                processed += batch.count
                // Save periodically to avoid holding too many changes in memory
                if changed && processed % batchSize == 0 {
                    context.safeSave()
                    changed = false // Reset for next batch
                }
            }

            // Final save if there are remaining changes
            if changed {
                context.safeSave()
            }
        }
    }

    /// Backfill isPresented flag from givenAt field.
    /// One-time migration: if givenAt is set, isPresented should be true.
    /// Idempotent: guarded by a UserDefaults flag.
    static func backfillIsPresentedIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.isPresentedFromGivenAt.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            let sls = context.safeFetch(FetchDescriptor<StudentLesson>())
            let batchSize = BatchingConstants.defaultBatchSize
            var changed = false

            for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                if batchStart % 500 == 0 {
                    await Task.yield()
                }

                let batchEnd = min(batchStart + batchSize, sls.count)
                let batch = Array(sls[batchStart..<batchEnd])

                for sl in batch {
                    if sl.givenAt != nil && sl.isPresented == false {
                        sl.isPresented = true
                        changed = true
                    }
                }

                if changed && (batchEnd % batchSize == 0 || batchEnd == sls.count) {
                    context.safeSave()
                    changed = false
                }
            }
        }
    }

    /// Backfill scheduledForDay field from scheduledFor.
    /// One-time migration that ensures scheduledForDay matches scheduledFor for all records.
    /// Idempotent: guarded by a UserDefaults flag.
    static func backfillScheduledForDayIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.scheduledForDay.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            let sls = context.safeFetch(FetchDescriptor<StudentLesson>())
            let batchSize = BatchingConstants.defaultBatchSize
            var needsSave = false

            for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                if batchStart % 500 == 0 {
                    await Task.yield()
                }

                let batchEnd = min(batchStart + batchSize, sls.count)
                let batch = Array(sls[batchStart..<batchEnd])

                for sl in batch {
                    let correct = sl.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
                    if sl.scheduledForDay != correct {
                        sl.scheduledForDay = correct
                        needsSave = true
                    }
                }

                if needsSave && (batchEnd % batchSize == 0 || batchEnd == sls.count) {
                    context.safeSave()
                    needsSave = false
                }
            }
        }
    }

    // MARK: - Run All Relationship Backfills

    /// Runs all relationship backfill migrations in sequence.
    /// Safe to call repeatedly - each migration is idempotent.
    static func runAllRelationshipBackfills(using context: ModelContext) async {
        await backfillRelationshipsIfNeeded(using: context)
        await backfillIsPresentedIfNeeded(using: context)
        await backfillScheduledForDayIfNeeded(using: context)
    }
}
