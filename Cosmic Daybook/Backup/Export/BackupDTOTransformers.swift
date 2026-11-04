import Foundation
import CoreData
import OSLog

/// Handles transformation between domain models and backup DTOs.
///
/// This extracts the DTO transformation logic from BackupService for better
/// testability and separation of concerns.
///
/// Transformers are organized into domain-specific extensions:
/// - `BackupDTOTransformers+V18Entities.swift` — CDDayPad, CDYearPlanEntry,
///   CDLessonSequenceSettings, CDStory, Book Club entities
/// - `BackupDTOTransformers+Misc.swift` — Todo, CDTrackEntity, CDSupply,
///   CDSchedule, CDIssue, CDProcedure, CDDocument, and remaining types
///
/// The types backed up through `ModelRow` (ModelRowKinds*.swift) are exported
/// by their specs, not here. Duplicating them here caused silent field loss in
/// the past — keep a single transformer per entity.
enum BackupDTOTransformers {
    // MARK: - WorkPlanItem - REMOVED IN PHASE 6
    // WorkPlanItem has been migrated to CDWorkCheckIn and removed from schema

    // MARK: - CDPresentation (Removed)
    // CDPresentation model has been removed. Use CDLessonAssignment instead.
}
