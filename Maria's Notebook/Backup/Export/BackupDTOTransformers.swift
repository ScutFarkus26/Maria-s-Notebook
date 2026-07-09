import Foundation
import CoreData
import OSLog

/// Handles transformation between domain models and backup DTOs.
///
/// This extracts the DTO transformation logic from BackupService for better
/// testability and separation of concerns.
///
/// Transformers are organized into domain-specific extensions:
/// - `BackupDTOTransformers+Core.swift` — CDLessonAttachment,
///   CDLessonPresentation, CDLessonRecallCheck, CDSampleWork, CDSampleWorkStep
/// - `BackupDTOTransformers+Work.swift` — CDWorkCheckIn, CDWorkStep,
///   WorkParticipant, CDPracticeSession
/// - `BackupDTOTransformers+V18Entities.swift` — CDDayPad, CDYearPlanEntry,
///   CDLessonSequenceSettings, CDStory, Book Club entities
/// - `BackupDTOTransformers+Misc.swift` — Calendar, Todo, CDTrackEntity,
///   CDSupply, CDSchedule, CDIssue, CDProcedure, CDDocument, and remaining types
///
/// Entities NOT handled here (CDStudent, CDLesson, CDNote, CDNonSchoolDay,
/// CDSchoolDayOverride, CDStudentMeeting, CDAttendanceRecord,
/// CDWorkCompletionRecord, CDProject, CDProjectSession, CDProjectRole, and the
/// Community entities) are exported via `BackupServiceHelpers.toDTOs`, which
/// carries their full field set. Duplicating them here caused silent field loss
/// in the past — keep a single transformer per entity.
enum BackupDTOTransformers {
    static let logger = Logger.backup

    // MARK: - LegacyPresentation (removed — model fully migrated to CDLessonAssignment)
    // LegacyPresentationDTO is kept for import backward compatibility only.

    // MARK: - WorkPlanItem - REMOVED IN PHASE 6
    // WorkPlanItem has been migrated to CDWorkCheckIn and removed from schema

    // MARK: - CDPresentation (Removed)
    // CDPresentation model has been removed. Use CDLessonAssignment instead.
}
