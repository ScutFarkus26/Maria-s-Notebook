import Foundation
import SwiftData

// MARK: - Misc Transformers (Calendar, Todo, Track, Supply, Schedule, Issue, Procedure, Document, etc.)

extension BackupDTOTransformers {

    // MARK: - NonSchoolDay

    static func toDTO(_ nonSchoolDay: NonSchoolDay) -> NonSchoolDayDTO {
        NonSchoolDayDTO(id: nonSchoolDay.id, date: nonSchoolDay.date, reason: nonSchoolDay.reason)
    }

    // MARK: - SchoolDayOverride

    static func toDTO(_ override: SchoolDayOverride) -> SchoolDayOverrideDTO {
        SchoolDayOverrideDTO(id: override.id, date: override.date)
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
            migratedFromLegacyID: assignment.migratedFromStudentLessonID,
            migratedFromPresentationID: assignment.migratedFromPresentationID
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
            absenceReason: record.absenceReason.rawValue == "none" ? nil : record.absenceReason.rawValue
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
            completedAt: record.completedAt
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
            isActive: e.isActive
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

    // MARK: - Batch Transformations (Misc)

    static func toDTOs(_ nonSchoolDays: [NonSchoolDay]) -> [NonSchoolDayDTO] {
        nonSchoolDays.map { toDTO($0) }
    }

    static func toDTOs(_ overrides: [SchoolDayOverride]) -> [SchoolDayOverrideDTO] {
        overrides.map { toDTO($0) }
    }

    static func toDTOs(_ meetings: [StudentMeeting]) -> [StudentMeetingDTO] {
        meetings.compactMap { toDTO($0) }
    }

    static func toDTOs(_ assignments: [LessonAssignment]) -> [LessonAssignmentDTO] {
        assignments.map { toDTO($0) }
    }

    static func toDTOs(_ records: [AttendanceRecord]) -> [AttendanceRecordDTO] {
        records.compactMap { toDTO($0) }
    }

    static func toDTOs(_ records: [WorkCompletionRecord]) -> [WorkCompletionRecordDTO] {
        records.compactMap { toDTO($0) }
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
