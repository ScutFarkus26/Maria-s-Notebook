import Foundation
import CoreData
import OSLog

// MARK: - Relationship Backfill Service

/// Service responsible for backfilling relationships between entities.
/// Legacy backfill methods are no longer needed (model removed).
/// Remaining backfills operate on other model types.
enum RelationshipBackfillService {
    private static let logger = Logger.migration

    // MARK: - WorkCompletionRecord Backfill

    /// Backfill WorkCompletionRecord entries from WorkParticipantEntity.completedAt data.
    /// This ensures all historical completion data is preserved in the WorkCompletionRecord system.
    /// Safe to run multiple times (idempotent - won't create duplicates).
    @MainActor
    static func backfillWorkCompletionRecords(using context: NSManagedObjectContext) {
        let flagKey = "Backfill.workCompletionRecords.v1"
        MigrationFlag.runIfNeeded(key: flagKey) {
            let allWork = context.safeFetch(CDFetchRequest(CDWorkModel.self))

            var totalBackfilled = 0
            var totalSkipped = 0

            for work in allWork {
                let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
                guard !participants.isEmpty else { continue }
                let workID = work.id ?? UUID()

                do {
                    let beforeCount = try WorkCompletionService.records(for: workID, in: context).count
                    try WorkCompletionBackfill.backfill(for: workID, participants: participants, in: context)
                    let afterCount = try WorkCompletionService.records(for: workID, in: context).count

                    let created = afterCount - beforeCount
                    if created > 0 {
                        totalBackfilled += created
                    } else {
                        totalSkipped += participants.count
                    }
                } catch {
                    logger.error("Error backfilling work \(workID, privacy: .public): \(error.localizedDescription)")
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
    @MainActor
    static func migrateWorkTypeToKind(using context: NSManagedObjectContext) {
        let flagKey = "Migration.workTypeToKind.v1"
        MigrationFlag.runIfNeeded(key: flagKey) {
            let allWork = context.safeFetch(CDFetchRequest(CDWorkModel.self))

            var migrated = 0

            for work in allWork {
                guard work.kindRaw == nil else { continue }

                let workKind: WorkKind = switch work.workTypeRaw {
                case "Practice": .practiceLesson
                case "Follow Up": .followUpAssignment
                case "Report": .report
                default: .research
                }

                work.kindRaw = workKind.rawValue
                migrated += 1
            }

            if migrated > 0 {
                context.safeSave()
            }

            logger.info("Migrated \(migrated, privacy: .public) work items from WorkType to WorkKind")
        }
    }

    // Deprecated ModelContext bridge methods removed - no longer needed with Core Data.
}
