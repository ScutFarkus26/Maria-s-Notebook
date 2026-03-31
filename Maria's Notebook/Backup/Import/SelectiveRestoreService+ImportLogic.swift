// SelectiveRestoreService+ImportLogic.swift
// Entity-type import logic for selective restore

import Foundation
import CoreData
import OSLog

extension SelectiveRestoreService {
    private static let logger = Logger.backup

    struct ImportResult {
        let imported: Int
        let skipped: Int
        let warning: String
    }
}

extension SelectiveRestoreService {

    // MARK: - Import Entity Type

    func importEntityType(
        _ type: RestorableEntityType,
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        mode: BackupService.RestoreMode
    ) async throws -> ImportResult {
        switch type {
        case .students:
            return try importStudentEntities(from: payload, into: viewContext)
        case .lessons:
            return try importLessonEntities(from: payload, into: viewContext)
        case .notes:
            return try importNoteEntities(from: payload, into: viewContext)
        case .calendar:
            return try importCalendarEntities(from: payload, into: viewContext)
        case .meetings:
            return try importMeetingEntities(from: payload, into: viewContext)
        case .community:
            return try importCommunityEntities(from: payload, into: viewContext)
        case .attendance:
            return try importAttendanceEntities(from: payload, into: viewContext)
        case .workCompletions:
            return try importWorkCompletionEntities(from: payload, into: viewContext)
        case .projects:
            return try importProjectEntities(from: payload, into: viewContext)
        }
    }

    // MARK: - Entity Import Helpers

    private func importStudentEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws -> ImportResult {
        // Use cached lookup - O(1) instead of O(n) per entity
        let result = BackupEntityImporter.importStudents(
            payload.students,
            into: viewContext,
            existingCheck: { [studentsByID] id in studentsByID[id] }
        )
        // Update cache with newly imported students
        for (id, student) in result {
            studentsByID[id] = student
        }
        return ImportResult(
            imported: result.count,
            skipped: payload.students.count - result.count,
            warning: ""
        )
    }

    private func importLessonEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws -> ImportResult {
        let existingLessonIDs = Set(lessonsByID.keys)
        BackupEntityImporter.importLessons(
            payload.lessons,
            into: viewContext,
            existingCheck: { [lessonsByID] id in lessonsByID[id] }
        )
        // CDTrackEntity imported count
        let newLessons = payload.lessons.filter { !existingLessonIDs.contains($0.id) }
        // Refresh lesson cache for subsequent imports
        do {
            let allLessons = try viewContext.fetch(CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>)
            lessonsByID = Dictionary(uniqueKeysWithValues: allLessons.compactMap { l in l.id.map { ($0, l) } })
        } catch {
            Self.logger.warning("Failed to refresh lesson cache: \(error.localizedDescription, privacy: .public)")
        }
        return ImportResult(
            imported: newLessons.count,
            skipped: payload.lessons.count - newLessons.count,
            warning: ""
        )
    }

    private func importNoteEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws -> ImportResult {
        try BackupEntityImporter.importNotes(
            payload.notes,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "notes", entityName: "Note", in: viewContext),
            lessonCheck: { [lessonsByID] id in lessonsByID[id] }
        )
        return ImportResult(imported: payload.notes.count, skipped: 0, warning: "")
    }

    private func importCalendarEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws -> ImportResult {
        try BackupEntityImporter.importNonSchoolDays(
            payload.nonSchoolDays,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "nonSchoolDays", entityName: "NonSchoolDay", in: viewContext)
        )
        try BackupEntityImporter.importSchoolDayOverrides(
            payload.schoolDayOverrides,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "schoolDayOverrides", entityName: "SchoolDayOverride", in: viewContext)
        )
        return ImportResult(
            imported: payload.nonSchoolDays.count + payload.schoolDayOverrides.count,
            skipped: 0, warning: ""
        )
    }

    private func importMeetingEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws -> ImportResult {
        try BackupEntityImporter.importStudentMeetings(
            payload.studentMeetings,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "studentMeetings", entityName: "StudentMeeting", in: viewContext)
        )
        return ImportResult(imported: payload.studentMeetings.count, skipped: 0, warning: "")
    }

    private func importCommunityEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws -> ImportResult {
        try BackupEntityImporter.importCommunityTopics(
            payload.communityTopics,
            into: viewContext,
            existingCheck: { [topicsByID] id in topicsByID[id] }
        )
        // Refresh topic cache for subsequent imports
        do {
            let allTopics = try viewContext.fetch(CDCommunityTopicEntity.fetchRequest() as! NSFetchRequest<CDCommunityTopicEntity>)
            topicsByID = Dictionary(uniqueKeysWithValues: allTopics.compactMap { t in t.id.map { ($0, t) } })
        } catch {
            Self.logger.warning("Failed to refresh topic cache: \(error.localizedDescription, privacy: .public)")
        }

        try BackupEntityImporter.importProposedSolutions(
            payload.proposedSolutions,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "proposedSolutions", entityName: "ProposedSolution", in: viewContext),
            topicCheck: { [topicsByID] id in topicsByID[id] }
        )
        try BackupEntityImporter.importCommunityAttachments(
            payload.communityAttachments,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "communityAttachments", entityName: "CommunityAttachment", in: viewContext),
            topicCheck: { [topicsByID] id in topicsByID[id] }
        )
        return ImportResult(
            imported: payload.communityTopics.count + payload.proposedSolutions.count
                + payload.communityAttachments.count,
            skipped: 0, warning: ""
        )
    }

    private func importAttendanceEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws -> ImportResult {
        try BackupEntityImporter.importAttendanceRecords(
            payload.attendance,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "attendanceRecords", entityName: "AttendanceRecord", in: viewContext)
        )
        return ImportResult(imported: payload.attendance.count, skipped: 0, warning: "")
    }

    private func importWorkCompletionEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws -> ImportResult {
        try BackupEntityImporter.importWorkCompletionRecords(
            payload.workCompletions,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "workCompletionRecords", entityName: "WorkCompletionRecord", in: viewContext)
        )
        return ImportResult(imported: payload.workCompletions.count, skipped: 0, warning: "")
    }

    private func importProjectEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws -> ImportResult {
        try BackupEntityImporter.importProjects(
            payload.projects,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "projects", entityName: "Project", in: viewContext)
        )
        try BackupEntityImporter.importProjectRoles(
            payload.projectRoles,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "projectRoles", entityName: "ProjectRole", in: viewContext)
        )
        try BackupEntityImporter.importProjectTemplateWeeks(
            payload.projectTemplateWeeks,
            into: viewContext,
            existingCheck: { [templateWeeksByID] id in templateWeeksByID[id] }
        )
        // Refresh template weeks cache for subsequent imports
        do {
            let allWeeks = try viewContext.fetch(CDProjectTemplateWeek.fetchRequest() as! NSFetchRequest<CDProjectTemplateWeek>)
            templateWeeksByID = Dictionary(uniqueKeysWithValues: allWeeks.compactMap { w in w.id.map { ($0, w) } })
        } catch {
            let desc = error.localizedDescription
            Self.logger.warning("Failed to refresh template weeks cache: \(desc, privacy: .public)")
        }

        try importProjectDetailEntities(from: payload, into: viewContext)

        let total = payload.projects.count + payload.projectAssignmentTemplates.count +
            payload.projectSessions.count + payload.projectRoles.count +
            payload.projectTemplateWeeks.count + payload.projectWeekRoleAssignments.count
        return ImportResult(imported: total, skipped: 0, warning: "")
    }

    private func importProjectDetailEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        try BackupEntityImporter.importProjectAssignmentTemplates(
            payload.projectAssignmentTemplates,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "projectAssignmentTemplates", entityName: "ProjectAssignmentTemplate", in: viewContext)
        )
        try BackupEntityImporter.importProjectWeekRoleAssignments(
            payload.projectWeekRoleAssignments,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "projectWeekRoleAssignments", entityName: "ProjectWeekRoleAssignment", in: viewContext),
            weekCheck: { [templateWeeksByID] id in templateWeeksByID[id] }
        )
        try BackupEntityImporter.importProjectSessions(
            payload.projectSessions,
            into: viewContext,
            existingCheck: cachedExistenceCheck(key: "projectSessions", entityName: "ProjectSession", in: viewContext)
        )
    }
}
