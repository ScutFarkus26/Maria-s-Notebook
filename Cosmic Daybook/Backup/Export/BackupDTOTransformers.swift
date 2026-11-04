import Foundation
import CoreData
import OSLog

/// Handles transformation between domain models and backup DTOs.
///
/// This extracts the DTO transformation logic from BackupService for better
/// testability and separation of concerns.
///
/// Transformers are organized into domain-specific extensions:
/// - `BackupDTOTransformers+Misc.swift` — Todo, CDScheduleSlot, CDIssue,
///   development snapshots, and remaining types
/// - `BackupDTOTransformers+Albums.swift` — album highlights and ink
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
