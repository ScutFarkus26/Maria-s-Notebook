import Foundation
import SwiftData

/// Handles transformation between domain models and backup DTOs.
///
/// This extracts the DTO transformation logic from BackupService for better
/// testability and separation of concerns.
enum BackupDTOTransformers {

    // MARK: - Student

    static func toDTO(_ student: Student) -> StudentDTO {
        let level: StudentDTO.Level = (student.level == .upper) ? .upper : .lower
        return StudentDTO(
            id: student.id,
            firstName: student.firstName,
            lastName: student.lastName,
            birthday: student.birthday,
            dateStarted: student.dateStarted,
            level: level,
            nextLessons: student.nextLessonUUIDs,
            manualOrder: student.manualOrder,
            createdAt: nil,
            updatedAt: nil
        )
    }

    // MARK: - Lesson

    static func toDTO(_ lesson: Lesson) -> LessonDTO {
        LessonDTO(
            id: lesson.id,
            name: lesson.name,
            subject: lesson.subject,
            group: lesson.group,
            orderInGroup: lesson.orderInGroup,
            subheading: lesson.subheading,
            writeUp: lesson.writeUp,
            createdAt: nil,
            updatedAt: nil,
            pagesFileRelativePath: lesson.pagesFileRelativePath
        )
    }

    // MARK: - StudentLesson

    static func toDTO(_ studentLesson: StudentLesson) -> StudentLessonDTO? {
        guard let lessonIDUUID = UUID(uuidString: studentLesson.lessonID) else {
            return nil
        }
        return StudentLessonDTO(
            id: studentLesson.id,
            lessonID: lessonIDUUID,
            studentIDs: studentLesson.resolvedStudentIDs,
            createdAt: studentLesson.createdAt,
            scheduledFor: studentLesson.scheduledFor,
            givenAt: studentLesson.givenAt,
            isPresented: studentLesson.isPresented,
            notes: studentLesson.notes,
            needsPractice: studentLesson.needsPractice,
            needsAnotherPresentation: studentLesson.needsAnotherPresentation,
            followUpWork: studentLesson.followUpWork,
            studentGroupKey: nil
        )
    }

    // MARK: - WorkPlanItem

    static func toDTO(_ workPlanItem: WorkPlanItem) -> WorkPlanItemDTO? {
        guard let workIDUUID = UUID(uuidString: workPlanItem.workID) else { return nil }
        return WorkPlanItemDTO(
            id: workPlanItem.id,
            workID: workIDUUID,
            scheduledDate: workPlanItem.scheduledDate,
            reason: workPlanItem.reasonRaw ?? (workPlanItem.reason?.rawValue ?? ""),
            note: workPlanItem.note
        )
    }

    // MARK: - Note

    static func toDTO(_ note: Note) -> NoteDTO {
        let scopeString: String
        if let data = try? JSONEncoder().encode(note.scope) {
            scopeString = String(data: data, encoding: .utf8) ?? "{}"
        } else {
            scopeString = "{}"
        }

        return NoteDTO(
            id: note.id,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            body: note.body,
            isPinned: note.isPinned,
            scope: scopeString,
            lessonID: note.lesson?.id,
            imagePath: note.imagePath
        )
    }

    // MARK: - NonSchoolDay

    static func toDTO(_ nonSchoolDay: NonSchoolDay) -> NonSchoolDayDTO {
        NonSchoolDayDTO(id: nonSchoolDay.id, date: nonSchoolDay.date, reason: nonSchoolDay.reason)
    }

    // MARK: - SchoolDayOverride

    static func toDTO(_ override: SchoolDayOverride) -> SchoolDayOverrideDTO {
        SchoolDayOverrideDTO(id: override.id, date: override.date, note: override.note)
    }

    // MARK: - StudentMeeting

    static func toDTO(_ meeting: StudentMeeting) -> StudentMeetingDTO? {
        guard let studentIDUUID = UUID(uuidString: meeting.studentID) else { return nil }
        return StudentMeetingDTO(
            id: meeting.id,
            studentID: studentIDUUID,
            date: meeting.date,
            completed: meeting.completed,
            reflection: meeting.reflection,
            focus: meeting.focus,
            requests: meeting.requests,
            guideNotes: meeting.guideNotes
        )
    }

    // MARK: - Presentation

    static func toDTO(_ presentation: Presentation) -> PresentationDTO {
        PresentationDTO(
            id: presentation.id,
            createdAt: presentation.createdAt,
            presentedAt: presentation.presentedAt,
            lessonID: presentation.lessonID,
            studentIDs: presentation.studentIDs,
            legacyStudentLessonID: presentation.legacyStudentLessonID,
            lessonTitleSnapshot: presentation.lessonTitleSnapshot,
            lessonSubtitleSnapshot: presentation.lessonSubtitleSnapshot
        )
    }

    // MARK: - CommunityTopic

    static func toDTO(_ topic: CommunityTopic) -> CommunityTopicDTO {
        CommunityTopicDTO(
            id: topic.id,
            title: topic.title,
            issueDescription: topic.issueDescription,
            createdAt: topic.createdAt,
            addressedDate: topic.addressedDate,
            resolution: topic.resolution,
            raisedBy: topic.raisedBy,
            tags: topic.tags
        )
    }

    // MARK: - ProposedSolution

    static func toDTO(_ solution: ProposedSolution) -> ProposedSolutionDTO {
        ProposedSolutionDTO(
            id: solution.id,
            topicID: solution.topic?.id,
            title: solution.title,
            details: solution.details,
            proposedBy: solution.proposedBy,
            createdAt: solution.createdAt,
            isAdopted: solution.isAdopted
        )
    }

    // MARK: - CommunityAttachment

    static func toDTO(_ attachment: CommunityAttachment) -> CommunityAttachmentDTO {
        CommunityAttachmentDTO(
            id: attachment.id,
            topicID: attachment.topic?.id,
            filename: attachment.filename,
            kind: attachment.kind.rawValue,
            createdAt: attachment.createdAt
        )
    }

    // MARK: - AttendanceRecord

    static func toDTO(_ record: AttendanceRecord) -> AttendanceRecordDTO? {
        guard let studentIDUUID = UUID(uuidString: record.studentID) else { return nil }
        return AttendanceRecordDTO(
            id: record.id,
            studentID: studentIDUUID,
            date: record.date,
            status: record.status.rawValue,
            absenceReason: record.absenceReason.rawValue == "none" ? nil : record.absenceReason.rawValue,
            note: record.note
        )
    }

    // MARK: - WorkCompletionRecord

    static func toDTO(_ record: WorkCompletionRecord) -> WorkCompletionRecordDTO? {
        guard let workIDUUID = UUID(uuidString: record.workID),
              let studentIDUUID = UUID(uuidString: record.studentID) else { return nil }
        return WorkCompletionRecordDTO(
            id: record.id,
            workID: workIDUUID,
            studentID: studentIDUUID,
            completedAt: record.completedAt,
            note: record.note
        )
    }

    // MARK: - Project

    static func toDTO(_ project: Project) -> ProjectDTO {
        ProjectDTO(
            id: project.id,
            createdAt: project.createdAt,
            title: project.title,
            bookTitle: project.bookTitle,
            memberStudentIDs: project.memberStudentIDs
        )
    }

    // MARK: - ProjectAssignmentTemplate

    static func toDTO(_ template: ProjectAssignmentTemplate) -> ProjectAssignmentTemplateDTO? {
        guard let projectIDUUID = UUID(uuidString: template.projectID) else { return nil }
        return ProjectAssignmentTemplateDTO(
            id: template.id,
            createdAt: template.createdAt,
            projectID: projectIDUUID,
            title: template.title,
            instructions: template.instructions,
            isShared: template.isShared,
            defaultLinkedLessonID: template.defaultLinkedLessonID
        )
    }

    // MARK: - ProjectSession

    static func toDTO(_ session: ProjectSession) -> ProjectSessionDTO? {
        guard let projectIDUUID = UUID(uuidString: session.projectID) else { return nil }
        let templateWeekIDUUID = session.templateWeekID.flatMap { UUID(uuidString: $0) }
        return ProjectSessionDTO(
            id: session.id,
            createdAt: session.createdAt,
            projectID: projectIDUUID,
            meetingDate: session.meetingDate,
            chapterOrPages: session.chapterOrPages,
            notes: session.notes,
            agendaItemsJSON: session.agendaItemsJSON,
            templateWeekID: templateWeekIDUUID
        )
    }

    // MARK: - ProjectRole

    static func toDTO(_ role: ProjectRole) -> ProjectRoleDTO? {
        guard let projectIDUUID = UUID(uuidString: role.projectID) else { return nil }
        return ProjectRoleDTO(
            id: role.id,
            createdAt: role.createdAt,
            projectID: projectIDUUID,
            title: role.title,
            summary: role.summary,
            instructions: role.instructions
        )
    }

    // MARK: - ProjectTemplateWeek

    static func toDTO(_ week: ProjectTemplateWeek) -> ProjectTemplateWeekDTO? {
        guard let projectIDUUID = UUID(uuidString: week.projectID) else { return nil }
        return ProjectTemplateWeekDTO(
            id: week.id,
            createdAt: week.createdAt,
            projectID: projectIDUUID,
            weekIndex: week.weekIndex,
            readingRange: week.readingRange,
            agendaItemsJSON: week.agendaItemsJSON,
            linkedLessonIDsJSON: week.linkedLessonIDsJSON,
            workInstructions: week.workInstructions
        )
    }

    // MARK: - ProjectWeekRoleAssignment

    static func toDTO(_ assignment: ProjectWeekRoleAssignment) -> ProjectWeekRoleAssignmentDTO? {
        guard let weekIDUUID = UUID(uuidString: assignment.weekID),
              let roleIDUUID = UUID(uuidString: assignment.roleID) else { return nil }
        return ProjectWeekRoleAssignmentDTO(
            id: assignment.id,
            createdAt: assignment.createdAt,
            weekID: weekIDUUID,
            studentID: assignment.studentID,
            roleID: roleIDUUID
        )
    }

    // MARK: - Batch Transformations

    static func toDTOs(_ students: [Student]) -> [StudentDTO] {
        students.map { toDTO($0) }
    }

    static func toDTOs(_ lessons: [Lesson]) -> [LessonDTO] {
        lessons.map { toDTO($0) }
    }

    static func toDTOs(_ studentLessons: [StudentLesson]) -> [StudentLessonDTO] {
        studentLessons.compactMap { toDTO($0) }
    }

    static func toDTOs(_ workPlanItems: [WorkPlanItem]) -> [WorkPlanItemDTO] {
        workPlanItems.compactMap { toDTO($0) }
    }

    static func toDTOs(_ notes: [Note]) -> [NoteDTO] {
        notes.map { toDTO($0) }
    }

    static func toDTOs(_ nonSchoolDays: [NonSchoolDay]) -> [NonSchoolDayDTO] {
        nonSchoolDays.map { toDTO($0) }
    }

    static func toDTOs(_ overrides: [SchoolDayOverride]) -> [SchoolDayOverrideDTO] {
        overrides.map { toDTO($0) }
    }

    static func toDTOs(_ meetings: [StudentMeeting]) -> [StudentMeetingDTO] {
        meetings.compactMap { toDTO($0) }
    }

    static func toDTOs(_ presentations: [Presentation]) -> [PresentationDTO] {
        presentations.map { toDTO($0) }
    }

    static func toDTOs(_ topics: [CommunityTopic]) -> [CommunityTopicDTO] {
        topics.map { toDTO($0) }
    }

    static func toDTOs(_ solutions: [ProposedSolution]) -> [ProposedSolutionDTO] {
        solutions.map { toDTO($0) }
    }

    static func toDTOs(_ attachments: [CommunityAttachment]) -> [CommunityAttachmentDTO] {
        attachments.map { toDTO($0) }
    }

    static func toDTOs(_ records: [AttendanceRecord]) -> [AttendanceRecordDTO] {
        records.compactMap { toDTO($0) }
    }

    static func toDTOs(_ records: [WorkCompletionRecord]) -> [WorkCompletionRecordDTO] {
        records.compactMap { toDTO($0) }
    }

    static func toDTOs(_ projects: [Project]) -> [ProjectDTO] {
        projects.map { toDTO($0) }
    }

    static func toDTOs(_ templates: [ProjectAssignmentTemplate]) -> [ProjectAssignmentTemplateDTO] {
        templates.compactMap { toDTO($0) }
    }

    static func toDTOs(_ sessions: [ProjectSession]) -> [ProjectSessionDTO] {
        sessions.compactMap { toDTO($0) }
    }

    static func toDTOs(_ roles: [ProjectRole]) -> [ProjectRoleDTO] {
        roles.compactMap { toDTO($0) }
    }

    static func toDTOs(_ weeks: [ProjectTemplateWeek]) -> [ProjectTemplateWeekDTO] {
        weeks.compactMap { toDTO($0) }
    }

    static func toDTOs(_ assignments: [ProjectWeekRoleAssignment]) -> [ProjectWeekRoleAssignmentDTO] {
        assignments.compactMap { toDTO($0) }
    }
}
