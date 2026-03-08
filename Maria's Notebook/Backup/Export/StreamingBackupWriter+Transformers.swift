import Foundation
import SwiftData

// MARK: - Entity DTO Transformers

extension StreamingBackupWriter {

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func transformToDTOs<T: PersistentModel>(_ entities: [T]) -> [Any] {
        switch entities {
        case let students as [Student]:
            return BackupDTOTransformers.toDTOs(students)
        case let lessons as [Lesson]:
            return BackupDTOTransformers.toDTOs(lessons)
        case let assignments as [LessonAssignment]:
            return BackupDTOTransformers.toDTOs(assignments)
        // WorkPlanItem removed in Phase 6 - migrated to WorkCheckIn
        case let notes as [Note]:
            return BackupDTOTransformers.toDTOs(notes)
        case let nonSchoolDays as [NonSchoolDay]:
            return BackupDTOTransformers.toDTOs(nonSchoolDays)
        case let overrides as [SchoolDayOverride]:
            return BackupDTOTransformers.toDTOs(overrides)
        case let meetings as [StudentMeeting]:
            return BackupDTOTransformers.toDTOs(meetings)
        case let topics as [CommunityTopic]:
            return BackupDTOTransformers.toDTOs(topics)
        case let solutions as [ProposedSolution]:
            return BackupDTOTransformers.toDTOs(solutions)
        case let attachments as [CommunityAttachment]:
            return BackupDTOTransformers.toDTOs(attachments)
        case let records as [AttendanceRecord]:
            return BackupDTOTransformers.toDTOs(records)
        case let completionRecords as [WorkCompletionRecord]:
            return BackupDTOTransformers.toDTOs(completionRecords)
        case let projects as [Project]:
            return BackupDTOTransformers.toDTOs(projects)
        case let templates as [ProjectAssignmentTemplate]:
            return BackupDTOTransformers.toDTOs(templates)
        case let sessions as [ProjectSession]:
            return BackupDTOTransformers.toDTOs(sessions)
        case let roles as [ProjectRole]:
            return BackupDTOTransformers.toDTOs(roles)
        case let weeks as [ProjectTemplateWeek]:
            return BackupDTOTransformers.toDTOs(weeks)
        case let roleAssignments as [ProjectWeekRoleAssignment]:
            return BackupDTOTransformers.toDTOs(roleAssignments)
        case let works as [WorkModel]:
            return BackupDTOTransformers.toDTOs(works)
        case let checkIns as [WorkCheckIn]:
            return BackupDTOTransformers.toDTOs(checkIns)
        case let steps as [WorkStep]:
            return BackupDTOTransformers.toDTOs(steps)
        case let participants as [WorkParticipantEntity]:
            return BackupDTOTransformers.toDTOs(participants)
        case let sessions as [PracticeSession]:
            return BackupDTOTransformers.toDTOs(sessions)
        case let attachments as [LessonAttachment]:
            return BackupDTOTransformers.toDTOs(attachments)
        case let presentations as [LessonPresentation]:
            return BackupDTOTransformers.toDTOs(presentations)
        case let sampleWorks as [SampleWork]:
            return BackupDTOTransformers.toDTOs(sampleWorks)
        case let sampleWorkSteps as [SampleWorkStep]:
            return BackupDTOTransformers.toDTOs(sampleWorkSteps)
        case let templates as [NoteTemplate]:
            return BackupDTOTransformers.toDTOs(templates)
        case let templates as [MeetingTemplate]:
            return BackupDTOTransformers.toDTOs(templates)
        case let reminders as [Reminder]:
            return BackupDTOTransformers.toDTOs(reminders)
        case let events as [CalendarEvent]:
            return BackupDTOTransformers.toDTOs(events)
        case let tracks as [Track]:
            return BackupDTOTransformers.toDTOs(tracks)
        case let steps as [TrackStep]:
            return BackupDTOTransformers.toDTOs(steps)
        case let enrollments as [StudentTrackEnrollment]:
            return BackupDTOTransformers.toDTOs(enrollments)
        case let groupTracks as [GroupTrack]:
            return BackupDTOTransformers.toDTOs(groupTracks)
        case let documents as [Document]:
            return BackupDTOTransformers.toDTOs(documents)
        case let supplies as [Supply]:
            return BackupDTOTransformers.toDTOs(supplies)
        case let transactions as [SupplyTransaction]:
            return BackupDTOTransformers.toDTOs(transactions)
        case let procedures as [Procedure]:
            return BackupDTOTransformers.toDTOs(procedures)
        case let schedules as [Schedule]:
            return BackupDTOTransformers.toDTOs(schedules)
        case let slots as [ScheduleSlot]:
            return BackupDTOTransformers.toDTOs(slots)
        case let issues as [Issue]:
            return BackupDTOTransformers.toDTOs(issues)
        case let actions as [IssueAction]:
            return BackupDTOTransformers.toDTOs(actions)
        case let snapshots as [DevelopmentSnapshot]:
            return BackupDTOTransformers.toDTOs(snapshots)
        case let items as [TodoItem]:
            return BackupDTOTransformers.toDTOs(items)
        case let subtasks as [TodoSubtask]:
            return BackupDTOTransformers.toDTOs(subtasks)
        case let templates as [TodoTemplate]:
            return BackupDTOTransformers.toDTOs(templates)
        case let orders as [TodayAgendaOrder]:
            return BackupDTOTransformers.toDTOs(orders)
        case let recommendations as [PlanningRecommendation]:
            return BackupDTOTransformers.toDTOs(recommendations)
        case let resources as [Resource]:
            return BackupDTOTransformers.toDTOs(resources)
        case let links as [NoteStudentLink]:
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
