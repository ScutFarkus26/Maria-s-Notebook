import Foundation
import CoreData
import OSLog

/// Handles transformation between domain models and backup DTOs.
///
/// This extracts the DTO transformation logic from BackupService for better
/// testability and separation of concerns.
///
/// Transformers are organized into domain-specific extensions:
/// - `BackupDTOTransformers+Core.swift` — CDStudent, CDLesson, CDNote,
///   LessonAttachment, CDLessonPresentation, CDSampleWork, CDSampleWorkStep
/// - `BackupDTOTransformers+Work.swift` — CDWorkCheckIn, CDWorkStep,
///   WorkParticipant, CDPracticeSession
/// - `BackupDTOTransformers+Projects.swift` — CDProject, CDProjectSession,
///   ProjectRole, ProjectTemplateWeek, ProjectWeekRoleAssignment,
///   CDCommunityTopicEntity, ProposedSolution, CommunityAttachment
/// - `BackupDTOTransformers+Misc.swift` — Calendar, Todo, CDTrackEntity,
///   CDSupply, CDSchedule, CDIssue, CDProcedure, CDDocument, and remaining types
enum BackupDTOTransformers {
    static let logger = Logger.backup

    // MARK: - LegacyPresentation (removed — model fully migrated to CDLessonAssignment)
    // LegacyPresentationDTO is kept for import backward compatibility only.

    // MARK: - WorkPlanItem - REMOVED IN PHASE 6
    // WorkPlanItem has been migrated to CDWorkCheckIn and removed from schema

    // MARK: - CDPresentation (Removed)
    // CDPresentation model has been removed. Use CDLessonAssignment instead.
}
