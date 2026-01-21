//
//  RepositoryContainer.swift
//  Maria's Notebook
//
//  Central factory/container for creating repositories.
//  Provides a single point of access for all repository instances.
//

import Foundation
import SwiftData

/// Central container that provides access to all repositories.
/// Use this to get repository instances with consistent context and save coordinator injection.
@MainActor
struct RepositoryContainer {
    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Core Repositories

    /// Repository for Student entities
    var students: StudentRepository {
        StudentRepository(context: context, saveCoordinator: saveCoordinator)
    }

    /// Repository for Lesson entities
    var lessons: LessonRepository {
        LessonRepository(context: context, saveCoordinator: saveCoordinator)
    }

    /// Repository for StudentLesson (presentation) entities
    var studentLessons: StudentLessonRepository {
        StudentLessonRepository(context: context, saveCoordinator: saveCoordinator)
    }

    /// Repository for Note entities
    var notes: NoteRepository {
        NoteRepository(context: context, saveCoordinator: saveCoordinator)
    }

    /// Repository for NoteTemplate entities
    var noteTemplates: NoteTemplateRepository {
        NoteTemplateRepository(context: context, saveCoordinator: saveCoordinator)
    }

    // MARK: - Attendance & Documents

    /// Repository for AttendanceRecord entities
    var attendance: AttendanceRepository {
        AttendanceRepository(context: context, saveCoordinator: saveCoordinator)
    }

    /// Repository for Document entities
    var documents: DocumentRepository {
        DocumentRepository(context: context, saveCoordinator: saveCoordinator)
    }

    // MARK: - Meetings & Reminders

    /// Repository for StudentMeeting entities
    var meetings: MeetingRepository {
        MeetingRepository(context: context, saveCoordinator: saveCoordinator)
    }

    /// Repository for Reminder entities
    var reminders: ReminderRepository {
        ReminderRepository(context: context, saveCoordinator: saveCoordinator)
    }

    // MARK: - Projects

    /// Repository for Project, ProjectSession, and ProjectAssignmentTemplate entities
    var projects: ProjectRepository {
        ProjectRepository(context: context, saveCoordinator: saveCoordinator)
    }

    // MARK: - Convenience Save

    /// Save changes using the save coordinator if available
    @discardableResult
    func save(reason: String? = nil) -> Bool {
        if let coordinator = saveCoordinator {
            return coordinator.save(context, reason: reason)
        }
        do {
            try context.save()
            return true
        } catch {
            return false
        }
    }
}
