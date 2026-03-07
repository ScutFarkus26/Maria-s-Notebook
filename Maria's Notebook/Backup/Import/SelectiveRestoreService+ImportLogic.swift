// SelectiveRestoreService+ImportLogic.swift
// Entity-type import logic for selective restore

import Foundation
import SwiftData

extension SelectiveRestoreService {
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
        into modelContext: ModelContext,
        mode: BackupService.RestoreMode
    ) async throws -> ImportResult {
        switch type {
        case .students:
            return try importStudentEntities(from: payload, into: modelContext)
        case .lessons:
            return try importLessonEntities(from: payload, into: modelContext)
        case .legacyPresentations:
            return try importLegacyPresentationEntities(from: payload, into: modelContext)
        case .notes:
            return importNoteEntities(from: payload, into: modelContext)
        case .calendar:
            return importCalendarEntities(from: payload, into: modelContext)
        case .meetings:
            return importMeetingEntities(from: payload, into: modelContext)
        case .community:
            return importCommunityEntities(from: payload, into: modelContext)
        case .attendance:
            return importAttendanceEntities(from: payload, into: modelContext)
        case .workCompletions:
            return importWorkCompletionEntities(from: payload, into: modelContext)
        case .projects:
            return try importProjectEntities(from: payload, into: modelContext)
        }
    }

    // MARK: - Entity Import Helpers

    private func importStudentEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws -> ImportResult {
        // Use cached lookup - O(1) instead of O(n) per entity
        let result = BackupEntityImporter.importStudents(
            payload.students,
            into: modelContext,
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
        into modelContext: ModelContext
    ) throws -> ImportResult {
        let existingLessonIDs = Set(lessonsByID.keys)
        BackupEntityImporter.importLessons(
            payload.lessons,
            into: modelContext,
            existingCheck: { [lessonsByID] id in lessonsByID[id] }
        )
        // Track imported count
        let newLessons = payload.lessons.filter { !existingLessonIDs.contains($0.id) }
        // Refresh lesson cache for subsequent imports
        do {
            let allLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
            lessonsByID = allLessons.toDictionary(by: \.id)
        } catch {
            print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to refresh lesson cache: \(error)")
        }
        return ImportResult(
            imported: newLessons.count,
            skipped: payload.lessons.count - newLessons.count,
            warning: ""
        )
    }

    private func importLegacyPresentationEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws -> ImportResult {
        // LegacyPresentation model removed — import as LessonAssignment
        try BackupEntityImporter.importLegacyPresentations(
            payload.legacyPresentations,
            into: modelContext,
            existingCheck: { [self] id in
                guard self.getCachedIDs("lessonAssignments").contains(id) else { return nil }
                let desc = FetchDescriptor<LessonAssignment>(
                    predicate: #Predicate { $0.id == id }
                )
                return try modelContext.fetch(desc).first
            },
            lessonCheck: { [lessonsByID] id in lessonsByID[id] },
            studentCheck: { [studentsByID] id in studentsByID[id] }
        )
        return ImportResult(imported: payload.legacyPresentations.count, skipped: 0, warning: "")
    }

    private func importNoteEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) -> ImportResult {
        BackupEntityImporter.importNotes(
            payload.notes,
            into: modelContext,
            existingCheck: { [self] id in
                self.getCachedIDs("notes").contains(id) ? Note(body: "", scope: .all) : nil
            },
            lessonCheck: { [lessonsByID] id in lessonsByID[id] }
        )
        return ImportResult(imported: payload.notes.count, skipped: 0, warning: "")
    }

    private func importCalendarEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) -> ImportResult {
        BackupEntityImporter.importNonSchoolDays(
            payload.nonSchoolDays,
            into: modelContext,
            existingCheck: { [self] id in
                self.getCachedIDs("nonSchoolDays").contains(id) ? NonSchoolDay(date: Date()) : nil
            }
        )
        BackupEntityImporter.importSchoolDayOverrides(
            payload.schoolDayOverrides,
            into: modelContext,
            existingCheck: { [self] id in
                self.getCachedIDs("schoolDayOverrides").contains(id) ? SchoolDayOverride(date: Date()) : nil
            }
        )
        return ImportResult(
            imported: payload.nonSchoolDays.count + payload.schoolDayOverrides.count,
            skipped: 0, warning: ""
        )
    }

    private func importMeetingEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) -> ImportResult {
        BackupEntityImporter.importStudentMeetings(
            payload.studentMeetings,
            into: modelContext,
            existingCheck: { [self] id in
                self.getCachedIDs("studentMeetings").contains(id)
                    ? StudentMeeting(studentID: UUID(), date: Date()) : nil
            }
        )
        return ImportResult(imported: payload.studentMeetings.count, skipped: 0, warning: "")
    }

    private func importCommunityEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) -> ImportResult {
        BackupEntityImporter.importCommunityTopics(
            payload.communityTopics,
            into: modelContext,
            existingCheck: { [topicsByID] id in topicsByID[id] }
        )
        // Refresh topic cache for subsequent imports
        do {
            let allTopics = try modelContext.fetch(FetchDescriptor<CommunityTopic>())
            topicsByID = allTopics.toDictionary(by: \.id)
        } catch {
            print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to refresh topic cache: \(error)")
        }

        BackupEntityImporter.importProposedSolutions(
            payload.proposedSolutions,
            into: modelContext,
            existingCheck: { [self] id in
                self.getCachedIDs("proposedSolutions").contains(id)
                    ? ProposedSolution(title: "", details: "", proposedBy: "", topic: nil) : nil
            },
            topicCheck: { [topicsByID] id in topicsByID[id] }
        )
        BackupEntityImporter.importCommunityAttachments(
            payload.communityAttachments,
            into: modelContext,
            existingCheck: { [self] id in
                self.getCachedIDs("communityAttachments").contains(id)
                    ? CommunityAttachment(filename: "", kind: .file, data: nil, topic: nil) : nil
            },
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
        into modelContext: ModelContext
    ) -> ImportResult {
        BackupEntityImporter.importAttendanceRecords(
            payload.attendance,
            into: modelContext,
            existingCheck: { [self] id in
                self.getCachedIDs("attendanceRecords").contains(id)
                    ? AttendanceRecord(studentID: UUID(), date: Date(), status: .unmarked) : nil
            }
        )
        return ImportResult(imported: payload.attendance.count, skipped: 0, warning: "")
    }

    private func importWorkCompletionEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) -> ImportResult {
        BackupEntityImporter.importWorkCompletionRecords(
            payload.workCompletions,
            into: modelContext,
            existingCheck: { [self] id in
                self.getCachedIDs("workCompletionRecords").contains(id)
                    ? WorkCompletionRecord(workID: UUID(), studentID: UUID(), completedAt: Date()) : nil
            }
        )
        return ImportResult(imported: payload.workCompletions.count, skipped: 0, warning: "")
    }

    private func importProjectEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws -> ImportResult {
        BackupEntityImporter.importProjects(
            payload.projects,
            into: modelContext,
            existingCheck: { [self] id in
                getCachedIDs("projects").contains(id) ? Project(title: "", bookTitle: nil, memberStudentIDs: []) : nil
            }
        )
        BackupEntityImporter.importProjectRoles(
            payload.projectRoles,
            into: modelContext,
            existingCheck: { [self] id in
                getCachedIDs("projectRoles").contains(id)
                    ? ProjectRole(projectID: UUID(), title: "", summary: "", instructions: "") : nil
            }
        )
        BackupEntityImporter.importProjectTemplateWeeks(
            payload.projectTemplateWeeks,
            into: modelContext,
            existingCheck: { [templateWeeksByID] id in templateWeeksByID[id] }
        )
        // Refresh template weeks cache for subsequent imports
        do {
            let allWeeks = try modelContext.fetch(FetchDescriptor<ProjectTemplateWeek>())
            templateWeeksByID = allWeeks.toDictionary(by: \.id)
        } catch {
            print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to refresh template weeks cache: \(error)")
        }

        try importProjectDetailEntities(from: payload, into: modelContext)

        let total = payload.projects.count + payload.projectAssignmentTemplates.count +
            payload.projectSessions.count + payload.projectRoles.count +
            payload.projectTemplateWeeks.count + payload.projectWeekRoleAssignments.count
        return ImportResult(imported: total, skipped: 0, warning: "")
    }

    private func importProjectDetailEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
        BackupEntityImporter.importProjectAssignmentTemplates(
            payload.projectAssignmentTemplates,
            into: modelContext,
            existingCheck: { [self] id in
                getCachedIDs("projectAssignmentTemplates").contains(id)
                    ? ProjectAssignmentTemplate(projectID: UUID(), title: "", instructions: "") : nil
            }
        )
        BackupEntityImporter.importProjectWeekRoleAssignments(
            payload.projectWeekRoleAssignments,
            into: modelContext,
            existingCheck: { [self] id in
                getCachedIDs("projectWeekRoleAssignments").contains(id)
                    ? ProjectWeekRoleAssignment(weekID: UUID(), studentID: "", roleID: UUID(), week: nil) : nil
            },
            weekCheck: { [templateWeeksByID] id in templateWeeksByID[id] }
        )
        BackupEntityImporter.importProjectSessions(
            payload.projectSessions,
            into: modelContext,
            existingCheck: { [self] id in
                getCachedIDs("projectSessions").contains(id)
                    ? ProjectSession(projectID: UUID(), meetingDate: Date()) : nil
            }
        )
    }
}
