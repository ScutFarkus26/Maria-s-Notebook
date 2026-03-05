// SelectiveRestoreService+ImportLogic.swift
// Entity-type import logic for selective restore

import Foundation
import SwiftData

extension SelectiveRestoreService {

    // MARK: - Import Entity Type

    func importEntityType(
        _ type: RestorableEntityType,
        from payload: BackupPayload,
        into modelContext: ModelContext,
        mode: BackupService.RestoreMode
    ) async throws -> (imported: Int, skipped: Int, warning: String) {

        var imported = 0
        var skipped = 0
        let warning = ""

        switch type {
        case .students:
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
            imported = result.count
            skipped = payload.students.count - result.count

        case .lessons:
            let existingLessonIDs = Set(lessonsByID.keys)
            BackupEntityImporter.importLessons(
                payload.lessons,
                into: modelContext,
                existingCheck: { [lessonsByID] id in lessonsByID[id] }
            )
            // Track imported count
            let newLessons = payload.lessons.filter { !existingLessonIDs.contains($0.id) }
            imported = newLessons.count
            skipped = payload.lessons.count - newLessons.count
            // Refresh lesson cache for subsequent imports
            do {
                let allLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
                lessonsByID = allLessons.toDictionary(by: \.id)
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to refresh lesson cache: \(error)")
            }

        case .legacyPresentations:
            // LegacyPresentation model removed — import as LessonAssignment
            try BackupEntityImporter.importLegacyPresentations(
                payload.legacyPresentations,
                into: modelContext,
                existingCheck: { [self] id in
                    guard self.getCachedIDs("lessonAssignments")
                        .contains(id) else { return nil }
                    let desc = FetchDescriptor<LessonAssignment>(
                        predicate: #Predicate { $0.id == id }
                    )
                    return try modelContext.fetch(desc).first
                },
                lessonCheck: { [lessonsByID] id in lessonsByID[id] },
                studentCheck: { [studentsByID] id in studentsByID[id] }
            )
            imported = payload.legacyPresentations.count

        case .notes:
            BackupEntityImporter.importNotes(
                payload.notes,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("notes").contains(id) ? Note(body: "", scope: .all) : nil
                },
                lessonCheck: { [lessonsByID] id in lessonsByID[id] }
            )
            imported = payload.notes.count

        case .calendar:
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
            imported = payload.nonSchoolDays.count + payload.schoolDayOverrides.count

        case .meetings:
            BackupEntityImporter.importStudentMeetings(
                payload.studentMeetings,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("studentMeetings").contains(id)
                        ? StudentMeeting(studentID: UUID(), date: Date())
                        : nil
                }
            )
            imported = payload.studentMeetings.count

        case .community:
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
                print("⚠️ [Backup:\(#function)] Failed to refresh topic cache: \(error)")
            }

            BackupEntityImporter.importProposedSolutions(
                payload.proposedSolutions,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("proposedSolutions").contains(id)
                        ? ProposedSolution(
                            title: "", details: "",
                            proposedBy: "", topic: nil
                        ) : nil
                },
                topicCheck: { [topicsByID] id in topicsByID[id] }
            )
            BackupEntityImporter.importCommunityAttachments(
                payload.communityAttachments,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("communityAttachments")
                        .contains(id)
                        ? CommunityAttachment(
                            filename: "", kind: .file,
                            data: nil, topic: nil
                        ) : nil
                },
                topicCheck: { [topicsByID] id in topicsByID[id] }
            )
            imported = payload.communityTopics.count
                + payload.proposedSolutions.count
                + payload.communityAttachments.count

        case .attendance:
            BackupEntityImporter.importAttendanceRecords(
                payload.attendance,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("attendanceRecords").contains(id)
                        ? AttendanceRecord(
                            studentID: UUID(), date: Date(),
                            status: .unmarked
                        ) : nil
                }
            )
            imported = payload.attendance.count

        case .workCompletions:
            BackupEntityImporter.importWorkCompletionRecords(
                payload.workCompletions,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("workCompletionRecords")
                        .contains(id)
                        ? WorkCompletionRecord(
                            workID: UUID(), studentID: UUID(),
                            completedAt: Date()
                        ) : nil
                }
            )
            imported = payload.workCompletions.count

        case .projects:
            BackupEntityImporter.importProjects(
                payload.projects,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("projects").contains(id)
                        ? Project(
                            title: "", bookTitle: nil,
                            memberStudentIDs: []
                        ) : nil
                }
            )
            BackupEntityImporter.importProjectRoles(
                payload.projectRoles,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("projectRoles").contains(id)
                        ? ProjectRole(
                            projectID: UUID(), title: "",
                            summary: "", instructions: ""
                        ) : nil
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
                print("⚠️ [Backup:\(#function)] Failed to refresh template weeks cache: \(error)")
            }

            BackupEntityImporter.importProjectAssignmentTemplates(
                payload.projectAssignmentTemplates,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("projectAssignmentTemplates")
                        .contains(id)
                        ? ProjectAssignmentTemplate(
                            projectID: UUID(), title: "",
                            instructions: ""
                        ) : nil
                }
            )
            BackupEntityImporter.importProjectWeekRoleAssignments(
                payload.projectWeekRoleAssignments,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("projectWeekRoleAssignments")
                        .contains(id)
                        ? ProjectWeekRoleAssignment(
                            weekID: UUID(), studentID: "",
                            roleID: UUID(), week: nil
                        ) : nil
                },
                weekCheck: { [templateWeeksByID] id in templateWeeksByID[id] }
            )
            BackupEntityImporter.importProjectSessions(
                payload.projectSessions,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("projectSessions").contains(id)
                        ? ProjectSession(
                            projectID: UUID(), meetingDate: Date()
                        ) : nil
                }
            )
            imported = payload.projects.count + payload.projectAssignmentTemplates.count +
                payload.projectSessions.count + payload.projectRoles.count +
                payload.projectTemplateWeeks.count + payload.projectWeekRoleAssignments.count
        }

        return (imported, skipped, warning)
    }
}
