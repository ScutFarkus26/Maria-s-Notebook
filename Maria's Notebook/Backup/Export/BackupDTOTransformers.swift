import Foundation
import SwiftData
import OSLog

/// Handles transformation between domain models and backup DTOs.
///
/// This extracts the DTO transformation logic from BackupService for better
/// testability and separation of concerns.
///
/// Transformers are organized into domain-specific extensions:
/// - `BackupDTOTransformers+Core.swift` — Student, Lesson, Note,
///   LessonExercise, LessonAttachment, LessonPresentation
/// - `BackupDTOTransformers+Work.swift` — WorkCheckIn, WorkStep,
///   WorkParticipant, PracticeSession
/// - `BackupDTOTransformers+Projects.swift` — Project, ProjectSession,
///   ProjectRole, ProjectTemplateWeek, ProjectWeekRoleAssignment,
///   CommunityTopic, ProposedSolution, CommunityAttachment
/// - `BackupDTOTransformers+Misc.swift` — Calendar, Todo, Track,
///   Supply, Schedule, Issue, Procedure, Document, and remaining types
enum BackupDTOTransformers {
    static let logger = Logger.backup

    // MARK: - LegacyPresentation (removed — model fully migrated to LessonAssignment)
    // LegacyPresentationDTO is kept for import backward compatibility only.

    // MARK: - WorkPlanItem - REMOVED IN PHASE 6
    // WorkPlanItem has been migrated to WorkCheckIn and removed from schema

    // MARK: - Presentation (Removed)
    // Presentation model has been removed. Use LessonAssignment instead.
}
