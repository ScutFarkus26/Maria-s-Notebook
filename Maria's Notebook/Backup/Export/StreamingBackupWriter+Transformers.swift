import Foundation
import CoreData

// MARK: - Entity DTO Transformers

extension StreamingBackupWriter {

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func transformToDTOs<T: NSManagedObject>(_ entities: [T]) -> [Any] {
        switch entities {
        case let students as [CDStudent]:
            return BackupDTOTransformers.toDTOs(students)
        case let lessons as [CDLesson]:
            return BackupDTOTransformers.toDTOs(lessons)
        case let assignments as [CDLessonAssignment]:
            return BackupDTOTransformers.toDTOs(assignments)
        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        case let notes as [CDNote]:
            return BackupDTOTransformers.toDTOs(notes)
        case let nonSchoolDays as [CDNonSchoolDay]:
            return BackupDTOTransformers.toDTOs(nonSchoolDays)
        case let overrides as [CDSchoolDayOverride]:
            return BackupDTOTransformers.toDTOs(overrides)
        case let meetings as [CDStudentMeeting]:
            return BackupDTOTransformers.toDTOs(meetings)
        case let topics as [CDCommunityTopicEntity]:
            return BackupDTOTransformers.toDTOs(topics)
        case let solutions as [ProposedSolution]:
            return BackupDTOTransformers.toDTOs(solutions)
        case let attachments as [CommunityAttachment]:
            return BackupDTOTransformers.toDTOs(attachments)
        case let records as [CDAttendanceRecord]:
            return BackupDTOTransformers.toDTOs(records)
        case let completionRecords as [CDWorkCompletionRecord]:
            return BackupDTOTransformers.toDTOs(completionRecords)
        case let projects as [CDProject]:
            return BackupDTOTransformers.toDTOs(projects)
        case let templates as [ProjectAssignmentTemplate]:
            return BackupDTOTransformers.toDTOs(templates)
        case let sessions as [CDProjectSession]:
            return BackupDTOTransformers.toDTOs(sessions)
        case let roles as [ProjectRole]:
            return BackupDTOTransformers.toDTOs(roles)
        case let weeks as [ProjectTemplateWeek]:
            return BackupDTOTransformers.toDTOs(weeks)
        case let roleAssignments as [ProjectWeekRoleAssignment]:
            return BackupDTOTransformers.toDTOs(roleAssignments)
        case let works as [CDWorkModel]:
            return BackupDTOTransformers.toDTOs(works)
        case let checkIns as [CDWorkCheckIn]:
            return BackupDTOTransformers.toDTOs(checkIns)
        case let steps as [CDWorkStep]:
            return BackupDTOTransformers.toDTOs(steps)
        case let participants as [WorkParticipantEntity]:
            return BackupDTOTransformers.toDTOs(participants)
        case let sessions as [CDPracticeSession]:
            return BackupDTOTransformers.toDTOs(sessions)
        case let attachments as [LessonAttachment]:
            return BackupDTOTransformers.toDTOs(attachments)
        case let presentations as [CDLessonPresentation]:
            return BackupDTOTransformers.toDTOs(presentations)
        case let sampleWorks as [CDSampleWork]:
            return BackupDTOTransformers.toDTOs(sampleWorks)
        case let sampleWorkSteps as [CDSampleWorkStep]:
            return BackupDTOTransformers.toDTOs(sampleWorkSteps)
        case let templates as [CDNoteTemplate]:
            return BackupDTOTransformers.toDTOs(templates)
        case let templates as [CDMeetingTemplate]:
            return BackupDTOTransformers.toDTOs(templates)
        case let reminders as [CDReminder]:
            return BackupDTOTransformers.toDTOs(reminders)
        case let events as [CDCalendarEvent]:
            return BackupDTOTransformers.toDTOs(events)
        case let tracks as [CDTrackEntity]:
            return BackupDTOTransformers.toDTOs(tracks)
        case let steps as [TrackStep]:
            return BackupDTOTransformers.toDTOs(steps)
        case let enrollments as [CDStudentTrackEnrollmentEntity]:
            return BackupDTOTransformers.toDTOs(enrollments)
        case let groupTracks as [CDGroupTrack]:
            return BackupDTOTransformers.toDTOs(groupTracks)
        case let documents as [CDDocument]:
            return BackupDTOTransformers.toDTOs(documents)
        case let supplies as [CDSupply]:
            return BackupDTOTransformers.toDTOs(supplies)
        case let transactions as [SupplyTransaction]:
            return BackupDTOTransformers.toDTOs(transactions)
        case let procedures as [CDProcedure]:
            return BackupDTOTransformers.toDTOs(procedures)
        case let schedules as [CDSchedule]:
            return BackupDTOTransformers.toDTOs(schedules)
        case let slots as [CDScheduleSlot]:
            return BackupDTOTransformers.toDTOs(slots)
        case let issues as [CDIssue]:
            return BackupDTOTransformers.toDTOs(issues)
        case let actions as [IssueAction]:
            return BackupDTOTransformers.toDTOs(actions)
        case let snapshots as [DevelopmentSnapshot]:
            return BackupDTOTransformers.toDTOs(snapshots)
        case let items as [CDTodoItem]:
            return BackupDTOTransformers.toDTOs(items)
        case let subtasks as [CDTodoSubtask]:
            return BackupDTOTransformers.toDTOs(subtasks)
        case let templates as [CDTodoTemplate]:
            return BackupDTOTransformers.toDTOs(templates)
        case let orders as [CDTodayAgendaOrder]:
            return BackupDTOTransformers.toDTOs(orders)
        case let recommendations as [PlanningRecommendation]:
            return BackupDTOTransformers.toDTOs(recommendations)
        case let resources as [CDResource]:
            return BackupDTOTransformers.toDTOs(resources)
        case let links as [CDNoteStudentLink]:
            return BackupDTOTransformers.toDTOs(links)
        default:
            return []
        }
    }

    func buildPreferencesDTO() -> PreferencesDTO {
        // Reuse existing implementation from BackupService
        var values: [String: PreferenceValueDTO] = [:]

        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            if key.hasPrefix("Maria.") || key.hasPrefix("App.") {
                if let val = UserDefaults.standard.object(forKey: key) {
                    if let b = val as? Bool {
                        values[key] = .bool(b)
                    } else if let i = val as? Int {
                        values[key] = .int(i)
                    } else if let d = val as? Double {
                        values[key] = .double(d)
                    } else if let s = val as? String {
                        values[key] = .string(s)
                    } else if let data = val as? Data {
                        values[key] = .data(data)
                    } else if let date = val as? Date {
                        values[key] = .date(date)
                    }
                }
            }
        }

        return PreferencesDTO(values: values)
    }
}
