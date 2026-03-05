import Foundation
import SwiftData
import OSLog

// MARK: - Relationship Backfill Service

/// Service responsible for backfilling relationships between entities.
/// Legacy backfill methods are no longer needed (model removed).
/// Remaining backfills operate on other model types.
enum RelationshipBackfillService {
    private static let logger = Logger.migration

    // MARK: - Legacy Backfills (no-ops)

    /// Legacy model removed — backfill complete. Marks flag if not already set.
    static func backfillRelationshipsIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.relationships.v1"
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
        }
    }

    /// Legacy model removed — backfill complete. Marks flag if not already set.
    static func backfillIsPresentedIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.isPresentedFromGivenAt.v1"
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
        }
    }

    /// Legacy model removed — backfill complete. Marks flag if not already set.
    static func backfillScheduledForDayIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.scheduledForDay.v1"
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
        }
    }

    // MARK: - WorkCompletionRecord Backfill

    /// Backfill WorkCompletionRecord entries from WorkParticipantEntity.completedAt data.
    /// This ensures all historical completion data is preserved in the WorkCompletionRecord system.
    /// Safe to run multiple times (idempotent - won't create duplicates).
    static func backfillWorkCompletionRecords(using context: ModelContext) {
        let flagKey = "Backfill.workCompletionRecords.v1"
        MigrationFlag.runIfNeeded(key: flagKey) {
            let descriptor = FetchDescriptor<WorkModel>()
            let allWork = context.safeFetch(descriptor)

            var totalBackfilled = 0
            var totalSkipped = 0

            for work in allWork {
                guard let participants = work.participants, !participants.isEmpty else {
                    continue
                }

                do {
                    let beforeCount = try WorkCompletionService.records(for: work.id, in: context).count
                    try WorkCompletionBackfill.backfill(for: work.id, participants: participants, in: context)
                    let afterCount = try WorkCompletionService.records(for: work.id, in: context).count

                    let created = afterCount - beforeCount
                    if created > 0 {
                        totalBackfilled += created
                    } else {
                        totalSkipped += participants.count
                    }
                } catch {
                    logger.error("Error backfilling work \(work.id, privacy: .public): \(error.localizedDescription)")
                }
            }

            // swiftlint:disable:next line_length
            logger.info("WorkCompletionBackfill complete: \(totalBackfilled, privacy: .public) records created, \(totalSkipped, privacy: .public) already existed")
        }
    }

    // MARK: - WorkType to WorkKind Migration

    /// Migrate WorkModel.workTypeRaw to WorkModel.kindRaw format.
    /// This consolidates the dual type systems into a single WorkKind enum.
    /// Safe to run multiple times (idempotent).
    static func migrateWorkTypeToKind(using context: ModelContext) {
        let flagKey = "Migration.workTypeToKind.v1"
        MigrationFlag.runIfNeeded(key: flagKey) {
            let descriptor = FetchDescriptor<WorkModel>()
            let allWork = context.safeFetch(descriptor)

            var migrated = 0

            for work in allWork {
                guard work.kindRaw == nil else { continue }

                let workKind: WorkKind = switch work.workTypeRaw {
                case "Practice": .practiceLesson
                case "Follow Up": .followUpAssignment
                case "Report": .report
                default: .research
                }

                work.kind = workKind
                migrated += 1
            }

            if migrated > 0 {
                context.safeSave()
            }

            logger.info("Migrated \(migrated, privacy: .public) work items from WorkType to WorkKind")
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
