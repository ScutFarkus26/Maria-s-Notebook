import Foundation
import SwiftData
import OSLog

/// Handles transformation between domain models and backup DTOs.
///
/// This extracts the DTO transformation logic from BackupService for better
/// testability and separation of concerns.
enum BackupDTOTransformers {
    private static let logger = Logger.backup

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

    // MARK: - WorkPlanItem - REMOVED IN PHASE 6
    // WorkPlanItem has been migrated to WorkCheckIn and removed from schema

    // MARK: - Note

    static func toDTO(_ note: Note) -> NoteDTO {
        let scopeString: String
        do {
            let data = try JSONEncoder().encode(note.scope)
            scopeString = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            logger.warning("Failed to encode note scope: \(error)")
            scopeString = "{}"
        }

        return NoteDTO(
            id: note.id,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            body: note.body,
            isPinned: note.isPinned,
            scope: scopeString,
            tags: note.tags.isEmpty ? nil : note.tags,
            needsFollowUp: note.needsFollowUp ? true : nil,
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

    // MARK: - Presentation (Removed)
    // Presentation model has been removed. Use LessonAssignment instead.

    // MARK: - LessonAssignment

    static func toDTO(_ assignment: LessonAssignment) -> LessonAssignmentDTO {
        LessonAssignmentDTO(
            id: assignment.id,
            createdAt: assignment.createdAt,
            modifiedAt: assignment.modifiedAt,
            stateRaw: assignment.stateRaw,
            scheduledFor: assignment.scheduledFor,
            presentedAt: assignment.presentedAt,
            lessonID: assignment.lessonID,
            studentIDs: assignment.studentIDs,
            lessonTitleSnapshot: assignment.lessonTitleSnapshot,
            lessonSubheadingSnapshot: assignment.lessonSubheadingSnapshot,
            needsPractice: assignment.needsPractice,
            needsAnotherPresentation: assignment.needsAnotherPresentation,
            followUpWork: assignment.followUpWork,
            notes: assignment.notes,
            trackID: assignment.trackID,
            trackStepID: assignment.trackStepID,
            migratedFromStudentLessonID: assignment.migratedFromStudentLessonID,
            migratedFromPresentationID: assignment.migratedFromPresentationID
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

    // MARK: - WorkCheckIn

    static func toDTO(_ checkIn: WorkCheckIn) -> WorkCheckInDTO {
        WorkCheckInDTO(
            id: checkIn.id,
            workID: checkIn.workID,
            date: checkIn.date,
            statusRaw: checkIn.statusRaw,
            note: checkIn.note,
            purpose: checkIn.purpose
        )
    }

    // MARK: - WorkStep

    static func toDTO(_ step: WorkStep) -> WorkStepDTO {
        WorkStepDTO(
            id: step.id,
            workID: step.work?.id,
            orderIndex: step.orderIndex,
            title: step.title,
            instructions: step.instructions,
            completedAt: step.completedAt,
            notes: step.notes,
            createdAt: step.createdAt
        )
    }

    // MARK: - WorkParticipantEntity

    static func toDTO(_ participant: WorkParticipantEntity) -> WorkParticipantEntityDTO {
        WorkParticipantEntityDTO(
            id: participant.id,
            studentID: participant.studentID,
            completedAt: participant.completedAt,
            workID: participant.work?.id
        )
    }

    // MARK: - PracticeSession

    static func toDTO(_ session: PracticeSession) -> PracticeSessionDTO {
        PracticeSessionDTO(
            id: session.id,
            createdAt: session.createdAt,
            date: session.date,
            duration: session.duration,
            studentIDs: session.studentIDs,
            workItemIDs: session.workItemIDs,
            sharedNotes: session.sharedNotes,
            location: session.location,
            practiceQuality: session.practiceQuality,
            independenceLevel: session.independenceLevel,
            askedForHelp: session.askedForHelp,
            helpedPeer: session.helpedPeer,
            struggledWithConcept: session.struggledWithConcept,
            madeBreakthrough: session.madeBreakthrough,
            needsReteaching: session.needsReteaching,
            readyForCheckIn: session.readyForCheckIn,
            readyForAssessment: session.readyForAssessment,
            checkInScheduledFor: session.checkInScheduledFor,
            followUpActions: session.followUpActions,
            materialsUsed: session.materialsUsed
        )
    }

    // MARK: - LessonAttachment

    static func toDTO(_ attachment: LessonAttachment) -> LessonAttachmentDTO {
        LessonAttachmentDTO(
            id: attachment.id,
            fileName: attachment.fileName,
            fileRelativePath: attachment.fileRelativePath,
            attachedAt: attachment.attachedAt,
            fileType: attachment.fileType,
            fileSizeBytes: attachment.fileSizeBytes,
            scopeRaw: attachment.scopeRaw,
            notes: attachment.notes,
            lessonID: attachment.lesson?.id
        )
    }

    // MARK: - LessonPresentation

    static func toDTO(_ lp: LessonPresentation) -> LessonPresentationDTO {
        LessonPresentationDTO(
            id: lp.id,
            createdAt: lp.createdAt,
            studentID: lp.studentID,
            lessonID: lp.lessonID,
            presentationID: lp.presentationID,
            trackID: lp.trackID,
            trackStepID: lp.trackStepID,
            stateRaw: lp.stateRaw,
            presentedAt: lp.presentedAt,
            lastObservedAt: lp.lastObservedAt,
            masteredAt: lp.masteredAt,
            notes: lp.notes
        )
    }

    // MARK: - NoteTemplate

    static func toDTO(_ t: NoteTemplate) -> NoteTemplateDTO {
        NoteTemplateDTO(
            id: t.id,
            createdAt: t.createdAt,
            title: t.title,
            body: t.body,
            categoryRaw: t.legacyCategoryRaw,
            tags: t.tags.isEmpty ? nil : t.tags,
            sortOrder: t.sortOrder,
            isBuiltIn: t.isBuiltIn
        )
    }

    // MARK: - MeetingTemplate

    static func toDTO(_ t: MeetingTemplate) -> MeetingTemplateDTO {
        MeetingTemplateDTO(
            id: t.id,
            createdAt: t.createdAt,
            name: t.name,
            reflectionPrompt: t.reflectionPrompt,
            focusPrompt: t.focusPrompt,
            requestsPrompt: t.requestsPrompt,
            guideNotesPrompt: t.guideNotesPrompt,
            sortOrder: t.sortOrder,
            isActive: t.isActive,
            isBuiltIn: t.isBuiltIn
        )
    }

    // MARK: - Reminder

    static func toDTO(_ r: Reminder) -> ReminderDTO {
        ReminderDTO(
            id: r.id,
            title: r.title,
            notes: r.notes,
            dueDate: r.dueDate,
            isCompleted: r.isCompleted,
            completedAt: r.completedAt,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt
        )
    }

    // MARK: - CalendarEvent

    static func toDTO(_ e: CalendarEvent) -> CalendarEventDTO {
        CalendarEventDTO(
            id: e.id,
            title: e.title,
            startDate: e.startDate,
            endDate: e.endDate,
            location: e.location,
            notes: e.notes,
            isAllDay: e.isAllDay
        )
    }

    // MARK: - Track

    static func toDTO(_ t: Track) -> TrackDTO {
        TrackDTO(id: t.id, title: t.title, createdAt: t.createdAt)
    }

    // MARK: - TrackStep

    static func toDTO(_ s: TrackStep) -> TrackStepDTO {
        TrackStepDTO(
            id: s.id,
            trackID: s.track?.id,
            orderIndex: s.orderIndex,
            lessonTemplateID: s.lessonTemplateID,
            createdAt: s.createdAt
        )
    }

    // MARK: - StudentTrackEnrollment

    static func toDTO(_ e: StudentTrackEnrollment) -> StudentTrackEnrollmentDTO {
        StudentTrackEnrollmentDTO(
            id: e.id,
            createdAt: e.createdAt,
            studentID: e.studentID,
            trackID: e.trackID,
            startedAt: e.startedAt,
            isActive: e.isActive,
            notes: e.notes
        )
    }

    // MARK: - GroupTrack

    static func toDTO(_ g: GroupTrack) -> GroupTrackDTO {
        GroupTrackDTO(
            id: g.id,
            subject: g.subject,
            group: g.group,
            isSequential: g.isSequential,
            isExplicitlyDisabled: g.isExplicitlyDisabled,
            createdAt: g.createdAt
        )
    }

    // MARK: - Document

    static func toDTO(_ d: Document) -> DocumentDTO {
        DocumentDTO(
            id: d.id,
            title: d.title,
            category: d.category,
            uploadDate: d.uploadDate,
            studentID: d.student?.id
        )
    }

    // MARK: - Supply

    static func toDTO(_ s: Supply) -> SupplyDTO {
        SupplyDTO(
            id: s.id,
            name: s.name,
            categoryRaw: s.category.rawValue,
            location: s.location,
            currentQuantity: s.currentQuantity,
            minimumThreshold: s.minimumThreshold,
            reorderAmount: s.reorderAmount,
            unit: s.unit,
            notes: s.notes,
            createdAt: s.createdAt,
            modifiedAt: s.modifiedAt
        )
    }

    // MARK: - SupplyTransaction

    static func toDTO(_ t: SupplyTransaction) -> SupplyTransactionDTO {
        SupplyTransactionDTO(
            id: t.id,
            supplyID: t.supplyID,
            date: t.date,
            quantityChange: t.quantityChange,
            reason: t.reason
        )
    }

    // MARK: - Procedure

    static func toDTO(_ p: Procedure) -> ProcedureDTO {
        ProcedureDTO(
            id: p.id,
            title: p.title,
            summary: p.summary,
            content: p.content,
            categoryRaw: p.category.rawValue,
            icon: p.icon,
            relatedProcedureIDs: p.relatedProcedureIDs,
            createdAt: p.createdAt,
            modifiedAt: p.modifiedAt
        )
    }

    // MARK: - Schedule

    static func toDTO(_ s: Schedule) -> ScheduleDTO {
        ScheduleDTO(
            id: s.id,
            name: s.name,
            notes: s.notes,
            colorHex: s.colorHex,
            icon: s.icon,
            createdAt: s.createdAt,
            modifiedAt: s.modifiedAt
        )
    }

    // MARK: - ScheduleSlot

    static func toDTO(_ s: ScheduleSlot) -> ScheduleSlotDTO {
        ScheduleSlotDTO(
            id: s.id,
            scheduleID: s.scheduleID,
            studentID: s.studentID,
            weekdayRaw: s.weekday.rawValue,
            timeString: s.timeString,
            sortOrder: s.sortOrder,
            notes: s.notes,
            createdAt: s.createdAt,
            modifiedAt: s.modifiedAt
        )
    }

    // MARK: - Issue

    static func toDTO(_ i: Issue) -> IssueDTO {
        IssueDTO(
            id: i.id,
            createdAt: i.createdAt,
            updatedAt: i.updatedAt,
            modifiedAt: i.modifiedAt,
            title: i.title,
            issueDescription: i.issueDescription,
            categoryRaw: i.category.rawValue,
            priorityRaw: i.priority.rawValue,
            statusRaw: i.status.rawValue,
            studentIDs: i.studentIDs,
            location: i.location,
            resolvedAt: i.resolvedAt,
            resolutionSummary: i.resolutionSummary
        )
    }

    // MARK: - IssueAction

    static func toDTO(_ a: IssueAction) -> IssueActionDTO {
        IssueActionDTO(
            id: a.id,
            createdAt: a.createdAt,
            updatedAt: a.updatedAt,
            modifiedAt: a.modifiedAt,
            issueID: a.issueID,
            actionTypeRaw: a.actionType.rawValue,
            actionDescription: a.actionDescription,
            actionDate: a.actionDate,
            participantStudentIDs: a.participantStudentIDs,
            nextSteps: a.nextSteps,
            followUpRequired: a.followUpRequired,
            followUpDate: a.followUpDate,
            followUpCompleted: a.followUpCompleted
        )
    }

    // MARK: - DevelopmentSnapshot

    static func toDTO(_ s: DevelopmentSnapshot) -> DevelopmentSnapshotDTO {
        DevelopmentSnapshotDTO(
            id: s.id,
            studentID: s.studentID,
            generatedAt: s.generatedAt,
            lookbackDays: s.lookbackDays,
            analysisVersion: s.analysisVersion,
            overallProgress: s.overallProgress,
            keyStrengths: s.keyStrengths,
            areasForGrowth: s.areasForGrowth,
            developmentalMilestones: s.developmentalMilestones,
            observedPatterns: s.observedPatterns,
            behavioralTrends: s.behavioralTrends,
            socialEmotionalInsights: s.socialEmotionalInsights,
            recommendedNextLessons: s.recommendedNextLessons,
            suggestedPracticeFocus: s.suggestedPracticeFocus,
            interventionSuggestions: s.interventionSuggestions,
            totalNotesAnalyzed: s.totalNotesAnalyzed,
            practiceSessionsAnalyzed: s.practiceSessionsAnalyzed,
            workCompletionsAnalyzed: s.workCompletionsAnalyzed,
            averagePracticeQuality: s.averagePracticeQuality,
            independenceLevel: s.independenceLevel,
            rawAnalysisJSON: s.rawAnalysisJSON,
            userNotes: s.userNotes,
            isReviewed: s.isReviewed,
            sharedWithParents: s.sharedWithParents,
            sharedAt: s.sharedAt
        )
    }

    // MARK: - TodoItem

    static func toDTO(_ t: TodoItem) -> TodoItemDTO {
        TodoItemDTO(
            id: t.id,
            title: t.title,
            notes: t.notes,
            isCompleted: t.isCompleted,
            createdAt: t.createdAt,
            completedAt: t.completedAt,
            orderIndex: t.orderIndex,
            dueDate: t.dueDate,
            priorityRaw: t.priority.rawValue,
            recurrenceRaw: t.recurrence.rawValue,
            studentIDs: t.studentIDs,
            linkedWorkItemID: t.linkedWorkItemID,
            attachmentPaths: t.attachmentPaths,
            estimatedMinutes: t.estimatedMinutes,
            actualMinutes: t.actualMinutes,
            reminderDate: t.reminderDate,
            reflectionNotes: t.reflectionNotes,
            tags: t.tags,
            scheduledDate: t.scheduledDate,
            isSomeday: t.isSomeday,
            repeatAfterCompletion: t.repeatAfterCompletion,
            customIntervalDays: t.customIntervalDays,
            locationName: t.locationName,
            locationLatitude: t.locationLatitude,
            locationLongitude: t.locationLongitude,
            locationRadius: t.locationRadius,
            notifyOnEntry: t.notifyOnEntry,
            notifyOnExit: t.notifyOnExit
        )
    }

    // MARK: - TodoSubtask

    static func toDTO(_ s: TodoSubtask) -> TodoSubtaskDTO {
        TodoSubtaskDTO(
            id: s.id,
            todoID: s.todo?.id,
            title: s.title,
            isCompleted: s.isCompleted,
            orderIndex: s.orderIndex,
            createdAt: s.createdAt,
            completedAt: s.completedAt
        )
    }

    // MARK: - TodoTemplate

    static func toDTO(_ t: TodoTemplate) -> TodoTemplateDTO {
        TodoTemplateDTO(
            id: t.id,
            name: t.name,
            title: t.title,
            notes: t.notes,
            createdAt: t.createdAt,
            priorityRaw: t.priority.rawValue,
            defaultEstimatedMinutes: t.defaultEstimatedMinutes,
            defaultStudentIDs: t.defaultStudentIDs,
            useCount: t.useCount,
            tags: t.tags
        )
    }

    // MARK: - TodayAgendaOrder

    static func toDTO(_ a: TodayAgendaOrder) -> TodayAgendaOrderDTO {
        TodayAgendaOrderDTO(
            id: a.id,
            day: a.day,
            itemTypeRaw: a.itemTypeRaw,
            itemID: a.itemID,
            position: a.position
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

    // WorkPlanItem removed in Phase 6 - no longer backed up

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

    // Removed: toDTOs for Presentation - model no longer exists

    static func toDTOs(_ assignments: [LessonAssignment]) -> [LessonAssignmentDTO] {
        assignments.map { toDTO($0) }
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

    // Batch transformers for new entity types (format v8+)

    static func toDTOs(_ checkIns: [WorkCheckIn]) -> [WorkCheckInDTO] {
        checkIns.map { toDTO($0) }
    }

    static func toDTOs(_ steps: [WorkStep]) -> [WorkStepDTO] {
        steps.map { toDTO($0) }
    }

    static func toDTOs(_ participants: [WorkParticipantEntity]) -> [WorkParticipantEntityDTO] {
        participants.map { toDTO($0) }
    }

    static func toDTOs(_ sessions: [PracticeSession]) -> [PracticeSessionDTO] {
        sessions.map { toDTO($0) }
    }

    static func toDTOs(_ attachments: [LessonAttachment]) -> [LessonAttachmentDTO] {
        attachments.map { toDTO($0) }
    }

    static func toDTOs(_ presentations: [LessonPresentation]) -> [LessonPresentationDTO] {
        presentations.map { toDTO($0) }
    }

    static func toDTOs(_ templates: [NoteTemplate]) -> [NoteTemplateDTO] {
        templates.map { toDTO($0) }
    }

    static func toDTOs(_ templates: [MeetingTemplate]) -> [MeetingTemplateDTO] {
        templates.map { toDTO($0) }
    }

    static func toDTOs(_ reminders: [Reminder]) -> [ReminderDTO] {
        reminders.map { toDTO($0) }
    }

    static func toDTOs(_ events: [CalendarEvent]) -> [CalendarEventDTO] {
        events.map { toDTO($0) }
    }

    static func toDTOs(_ tracks: [Track]) -> [TrackDTO] {
        tracks.map { toDTO($0) }
    }

    static func toDTOs(_ steps: [TrackStep]) -> [TrackStepDTO] {
        steps.map { toDTO($0) }
    }

    static func toDTOs(_ enrollments: [StudentTrackEnrollment]) -> [StudentTrackEnrollmentDTO] {
        enrollments.map { toDTO($0) }
    }

    static func toDTOs(_ groupTracks: [GroupTrack]) -> [GroupTrackDTO] {
        groupTracks.map { toDTO($0) }
    }

    static func toDTOs(_ documents: [Document]) -> [DocumentDTO] {
        documents.map { toDTO($0) }
    }

    static func toDTOs(_ supplies: [Supply]) -> [SupplyDTO] {
        supplies.map { toDTO($0) }
    }

    static func toDTOs(_ transactions: [SupplyTransaction]) -> [SupplyTransactionDTO] {
        transactions.map { toDTO($0) }
    }

    static func toDTOs(_ procedures: [Procedure]) -> [ProcedureDTO] {
        procedures.map { toDTO($0) }
    }

    static func toDTOs(_ schedules: [Schedule]) -> [ScheduleDTO] {
        schedules.map { toDTO($0) }
    }

    static func toDTOs(_ slots: [ScheduleSlot]) -> [ScheduleSlotDTO] {
        slots.map { toDTO($0) }
    }

    static func toDTOs(_ issues: [Issue]) -> [IssueDTO] {
        issues.map { toDTO($0) }
    }

    static func toDTOs(_ actions: [IssueAction]) -> [IssueActionDTO] {
        actions.map { toDTO($0) }
    }

    static func toDTOs(_ snapshots: [DevelopmentSnapshot]) -> [DevelopmentSnapshotDTO] {
        snapshots.map { toDTO($0) }
    }

    static func toDTOs(_ items: [TodoItem]) -> [TodoItemDTO] {
        items.map { toDTO($0) }
    }

    static func toDTOs(_ subtasks: [TodoSubtask]) -> [TodoSubtaskDTO] {
        subtasks.map { toDTO($0) }
    }

    static func toDTOs(_ templates: [TodoTemplate]) -> [TodoTemplateDTO] {
        templates.map { toDTO($0) }
    }

    static func toDTOs(_ orders: [TodayAgendaOrder]) -> [TodayAgendaOrderDTO] {
        orders.map { toDTO($0) }
    }
}
