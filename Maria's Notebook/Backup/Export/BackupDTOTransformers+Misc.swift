// swiftlint:disable file_length
import Foundation
import CoreData

// MARK: - Misc Transformers (Calendar, Todo, CDTrackEntity, CDSupply, CDSchedule, CDIssue, CDProcedure, CDDocument, etc.)

extension BackupDTOTransformers {

    // MARK: - CDNonSchoolDay

    static func toDTO(_ nonSchoolDay: CDNonSchoolDay) -> NonSchoolDayDTO {
        NonSchoolDayDTO(id: nonSchoolDay.id ?? UUID(), date: nonSchoolDay.date ?? Date(), reason: nonSchoolDay.reason)
    }

    // MARK: - CDSchoolDayOverride

    static func toDTO(_ override: CDSchoolDayOverride) -> SchoolDayOverrideDTO {
        SchoolDayOverrideDTO(id: override.id ?? UUID(), date: override.date ?? Date())
    }

    // MARK: - CDStudentMeeting

    static func toDTO(_ meeting: CDStudentMeeting) -> StudentMeetingDTO? {
        guard let studentIDUUID = UUID(uuidString: meeting.studentID) else { return nil }
        return StudentMeetingDTO(
            id: meeting.id ?? UUID(),
            studentID: studentIDUUID,
            date: meeting.date ?? Date(),
            completed: meeting.completed,
            reflection: meeting.reflection,
            focus: meeting.focus,
            requests: meeting.requests,
            guideNotes: meeting.guideNotes
        )
    }

    // MARK: - CDLessonAssignment

    static func toDTO(_ assignment: CDLessonAssignment) -> LessonAssignmentDTO {
        LessonAssignmentDTO(
            id: assignment.id ?? UUID(),
            createdAt: assignment.createdAt ?? Date(),
            modifiedAt: assignment.modifiedAt ?? Date(),
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

    // MARK: - CDAttendanceRecord

    static func toDTO(_ record: CDAttendanceRecord) -> AttendanceRecordDTO? {
        guard let studentIDUUID = UUID(uuidString: record.studentID) else { return nil }
        return AttendanceRecordDTO(
            id: record.id ?? UUID(),
            studentID: studentIDUUID,
            date: record.date ?? Date(),
            status: record.status.rawValue,
            absenceReason: record.absenceReason.rawValue == "none" ? nil : record.absenceReason.rawValue
        )
    }

    // MARK: - CDWorkCompletionRecord

    static func toDTO(_ record: CDWorkCompletionRecord) -> WorkCompletionRecordDTO? {
        guard let workIDUUID = UUID(uuidString: record.workID),
              let studentIDUUID = UUID(uuidString: record.studentID) else { return nil }
        return WorkCompletionRecordDTO(
            id: record.id ?? UUID(),
            workID: workIDUUID,
            studentID: studentIDUUID,
            completedAt: record.completedAt ?? Date()
        )
    }

    // MARK: - CDNoteTemplate

    static func toDTO(_ t: CDNoteTemplate) -> NoteTemplateDTO {
        let tagsArray = (t.tags as? [String]) ?? []
        return NoteTemplateDTO(
            id: t.id ?? UUID(),
            createdAt: t.createdAt ?? Date(),
            title: t.title,
            body: t.body,
            categoryRaw: t.legacyCategoryRaw,
            tags: tagsArray.isEmpty ? nil : tagsArray,
            sortOrder: Int(t.sortOrder),
            isBuiltIn: t.isBuiltIn
        )
    }

    // MARK: - CDMeetingTemplate

    static func toDTO(_ t: CDMeetingTemplate) -> MeetingTemplateDTO {
        MeetingTemplateDTO(
            id: t.id ?? UUID(),
            createdAt: t.createdAt ?? Date(),
            name: t.name,
            reflectionPrompt: t.reflectionPrompt,
            focusPrompt: t.focusPrompt,
            requestsPrompt: t.requestsPrompt,
            guideNotesPrompt: t.guideNotesPrompt,
            sortOrder: Int(t.sortOrder),
            isActive: t.isActive,
            isBuiltIn: t.isBuiltIn
        )
    }

    // MARK: - CDReminder

    static func toDTO(_ r: CDReminder) -> ReminderDTO {
        ReminderDTO(
            id: r.id ?? UUID(),
            title: r.title,
            notes: r.notes,
            dueDate: r.dueDate,
            isCompleted: r.isCompleted,
            completedAt: r.completedAt,
            createdAt: r.createdAt ?? Date(),
            updatedAt: r.updatedAt ?? Date()
        )
    }

    // MARK: - CDCalendarEvent

    static func toDTO(_ e: CDCalendarEvent) -> CalendarEventDTO {
        CalendarEventDTO(
            id: e.id ?? UUID(),
            title: e.title,
            startDate: e.startDate ?? Date(),
            endDate: e.endDate ?? Date(),
            location: e.location,
            notes: e.notes,
            isAllDay: e.isAllDay
        )
    }

    // MARK: - CDTrackEntity

    static func toDTO(_ t: CDTrackEntity) -> TrackDTO {
        TrackDTO(id: t.id ?? UUID(), title: t.title, createdAt: t.createdAt ?? Date())
    }

    // MARK: - TrackStep

    static func toDTO(_ s: TrackStep) -> TrackStepDTO {
        TrackStepDTO(
            id: s.id ?? UUID(),
            trackID: s.track?.id,
            orderIndex: Int(s.orderIndex),
            lessonTemplateID: s.lessonTemplateID,
            createdAt: s.createdAt ?? Date()
        )
    }

    // MARK: - CDStudentTrackEnrollmentEntity

    static func toDTO(_ e: CDStudentTrackEnrollmentEntity) -> StudentTrackEnrollmentDTO {
        StudentTrackEnrollmentDTO(
            id: e.id ?? UUID(),
            createdAt: e.createdAt ?? Date(),
            studentID: e.studentID,
            trackID: e.trackID,
            startedAt: e.startedAt,
            isActive: e.isActive
        )
    }

    // MARK: - CDGroupTrack

    static func toDTO(_ g: CDGroupTrack) -> GroupTrackDTO {
        GroupTrackDTO(
            id: g.id ?? UUID(),
            subject: g.subject,
            group: g.group,
            isSequential: g.isSequential,
            isExplicitlyDisabled: g.isExplicitlyDisabled,
            createdAt: g.createdAt ?? Date()
        )
    }

    // MARK: - CDDocument

    static func toDTO(_ d: CDDocument) -> DocumentDTO {
        DocumentDTO(
            id: d.id ?? UUID(),
            title: d.title,
            category: d.category,
            uploadDate: d.uploadDate ?? Date(),
            studentID: d.student?.id
        )
    }

    // MARK: - CDSupply

    static func toDTO(_ s: CDSupply) -> SupplyDTO {
        SupplyDTO(
            id: s.id ?? UUID(),
            name: s.name,
            categoryRaw: s.category.rawValue,
            location: s.location,
            currentQuantity: Int(s.currentQuantity),
            minimumThreshold: Int(s.minimumThreshold),
            reorderAmount: Int(s.reorderAmount),
            unit: s.unit,
            notes: s.notes,
            createdAt: s.createdAt ?? Date(),
            modifiedAt: s.modifiedAt ?? Date()
        )
    }

    // MARK: - SupplyTransaction

    static func toDTO(_ t: SupplyTransaction) -> SupplyTransactionDTO {
        SupplyTransactionDTO(
            id: t.id ?? UUID(),
            supplyID: t.supplyID,
            date: t.date ?? Date(),
            quantityChange: Int(t.quantityChange),
            reason: t.reason
        )
    }

    // MARK: - CDProcedure

    static func toDTO(_ p: CDProcedure) -> ProcedureDTO {
        ProcedureDTO(
            id: p.id ?? UUID(),
            title: p.title,
            summary: p.summary,
            content: p.content,
            categoryRaw: p.category.rawValue,
            icon: p.icon,
            relatedProcedureIDs: p.relatedProcedureIDs,
            createdAt: p.createdAt ?? Date(),
            modifiedAt: p.modifiedAt ?? Date()
        )
    }

    // MARK: - CDSchedule

    static func toDTO(_ s: CDSchedule) -> ScheduleDTO {
        ScheduleDTO(
            id: s.id ?? UUID(),
            name: s.name,
            notes: s.notes,
            colorHex: s.colorHex,
            icon: s.icon,
            createdAt: s.createdAt ?? Date(),
            modifiedAt: s.modifiedAt ?? Date()
        )
    }

    // MARK: - CDScheduleSlot

    static func toDTO(_ s: CDScheduleSlot) -> ScheduleSlotDTO {
        ScheduleSlotDTO(
            id: s.id ?? UUID(),
            scheduleID: s.scheduleID,
            studentID: s.studentID,
            weekdayRaw: s.weekday.rawValue,
            timeString: s.timeString,
            sortOrder: Int(s.sortOrder),
            notes: s.notes,
            createdAt: s.createdAt ?? Date(),
            modifiedAt: s.modifiedAt ?? Date()
        )
    }

    // MARK: - CDIssue

    static func toDTO(_ i: CDIssue) -> IssueDTO {
        IssueDTO(
            id: i.id ?? UUID(),
            createdAt: i.createdAt ?? Date(),
            updatedAt: i.updatedAt ?? Date(),
            modifiedAt: i.modifiedAt ?? Date(),
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
            id: a.id ?? UUID(),
            createdAt: a.createdAt ?? Date(),
            updatedAt: a.updatedAt ?? Date(),
            modifiedAt: a.modifiedAt ?? Date(),
            issueID: a.issueID,
            actionTypeRaw: a.actionType.rawValue,
            actionDescription: a.actionDescription,
            actionDate: a.actionDate ?? Date(),
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
            id: s.id ?? UUID(),
            studentID: s.studentID,
            generatedAt: s.generatedAt ?? Date(),
            lookbackDays: Int(s.lookbackDays),
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
            totalNotesAnalyzed: Int(s.totalNotesAnalyzed),
            practiceSessionsAnalyzed: Int(s.practiceSessionsAnalyzed),
            workCompletionsAnalyzed: Int(s.workCompletionsAnalyzed),
            averagePracticeQuality: s.averagePracticeQuality,
            independenceLevel: s.independenceLevel,
            rawAnalysisJSON: s.rawAnalysisJSON,
            userNotes: s.userNotes,
            isReviewed: s.isReviewed,
            sharedWithParents: s.sharedWithParents,
            sharedAt: s.sharedAt
        )
    }

    // MARK: - CDTodoItem

    static func toDTO(_ t: CDTodoItem) -> TodoItemDTO {
        TodoItemDTO(
            id: t.id ?? UUID(),
            title: t.title,
            notes: t.notes,
            isCompleted: t.isCompleted,
            createdAt: t.createdAt ?? Date(),
            completedAt: t.completedAt,
            orderIndex: Int(t.orderIndex),
            dueDate: t.dueDate,
            priorityRaw: t.priority.rawValue,
            recurrenceRaw: t.recurrence.rawValue,
            studentIDs: (t.studentIDs as? [String]) ?? [],
            linkedWorkItemID: t.linkedWorkItemID,
            attachmentPaths: (t.attachmentPaths as? [String]) ?? [],
            estimatedMinutes: Int(t.estimatedMinutes),
            actualMinutes: Int(t.actualMinutes),
            reminderDate: t.reminderDate,
            reflectionNotes: t.reflectionNotes,
            tags: (t.tags as? [String]) ?? [],
            scheduledDate: t.scheduledDate,
            isSomeday: t.isSomeday,
            repeatAfterCompletion: t.repeatAfterCompletion,
            customIntervalDays: Int(t.customIntervalDays),
            locationName: t.locationName,
            locationLatitude: t.locationLatitude,
            locationLongitude: t.locationLongitude,
            locationRadius: t.locationRadius,
            notifyOnEntry: t.notifyOnEntry,
            notifyOnExit: t.notifyOnExit
        )
    }

    // MARK: - CDTodoSubtask

    static func toDTO(_ s: CDTodoSubtask) -> TodoSubtaskDTO {
        TodoSubtaskDTO(
            id: s.id ?? UUID(),
            todoID: s.todo?.id,
            title: s.title,
            isCompleted: s.isCompleted,
            orderIndex: Int(s.orderIndex),
            createdAt: s.createdAt ?? Date(),
            completedAt: s.completedAt
        )
    }

    // MARK: - CDTodoTemplate

    static func toDTO(_ t: CDTodoTemplate) -> TodoTemplateDTO {
        TodoTemplateDTO(
            id: t.id ?? UUID(),
            name: t.name,
            title: t.title,
            notes: t.notes,
            createdAt: t.createdAt ?? Date(),
            priorityRaw: t.priority.rawValue,
            defaultEstimatedMinutes: Int(t.defaultEstimatedMinutes),
            defaultStudentIDs: (t.defaultStudentIDs as? [String]) ?? [],
            useCount: Int(t.useCount),
            tags: (t.tags as? [String])
        )
    }

    // MARK: - CDTodayAgendaOrder

    static func toDTO(_ a: CDTodayAgendaOrder) -> TodayAgendaOrderDTO {
        TodayAgendaOrderDTO(
            id: a.id ?? UUID(),
            day: a.day ?? Date(),
            itemTypeRaw: a.itemTypeRaw,
            itemID: a.itemID ?? UUID(),
            position: Int(a.position)
        )
    }

    // MARK: - Batch Transformations (Misc)

    static func toDTOs(_ nonSchoolDays: [CDNonSchoolDay]) -> [NonSchoolDayDTO] {
        nonSchoolDays.map { toDTO($0) }
    }

    static func toDTOs(_ overrides: [CDSchoolDayOverride]) -> [SchoolDayOverrideDTO] {
        overrides.map { toDTO($0) }
    }

    static func toDTOs(_ meetings: [CDStudentMeeting]) -> [StudentMeetingDTO] {
        meetings.compactMap { toDTO($0) }
    }

    static func toDTOs(_ assignments: [CDLessonAssignment]) -> [LessonAssignmentDTO] {
        assignments.map { toDTO($0) }
    }

    static func toDTOs(_ records: [CDAttendanceRecord]) -> [AttendanceRecordDTO] {
        records.compactMap { toDTO($0) }
    }

    static func toDTOs(_ records: [CDWorkCompletionRecord]) -> [WorkCompletionRecordDTO] {
        records.compactMap { toDTO($0) }
    }

    static func toDTOs(_ templates: [CDNoteTemplate]) -> [NoteTemplateDTO] {
        templates.map { toDTO($0) }
    }

    static func toDTOs(_ templates: [CDMeetingTemplate]) -> [MeetingTemplateDTO] {
        templates.map { toDTO($0) }
    }

    static func toDTOs(_ reminders: [CDReminder]) -> [ReminderDTO] {
        reminders.map { toDTO($0) }
    }

    static func toDTOs(_ events: [CDCalendarEvent]) -> [CalendarEventDTO] {
        events.map { toDTO($0) }
    }

    static func toDTOs(_ tracks: [CDTrackEntity]) -> [TrackDTO] {
        tracks.map { toDTO($0) }
    }

    static func toDTOs(_ steps: [TrackStep]) -> [TrackStepDTO] {
        steps.map { toDTO($0) }
    }

    static func toDTOs(_ enrollments: [CDStudentTrackEnrollmentEntity]) -> [StudentTrackEnrollmentDTO] {
        enrollments.map { toDTO($0) }
    }

    static func toDTOs(_ groupTracks: [CDGroupTrack]) -> [GroupTrackDTO] {
        groupTracks.map { toDTO($0) }
    }

    static func toDTOs(_ documents: [CDDocument]) -> [DocumentDTO] {
        documents.map { toDTO($0) }
    }

    static func toDTOs(_ supplies: [CDSupply]) -> [SupplyDTO] {
        supplies.map { toDTO($0) }
    }

    static func toDTOs(_ transactions: [SupplyTransaction]) -> [SupplyTransactionDTO] {
        transactions.map { toDTO($0) }
    }

    static func toDTOs(_ procedures: [CDProcedure]) -> [ProcedureDTO] {
        procedures.map { toDTO($0) }
    }

    static func toDTOs(_ schedules: [CDSchedule]) -> [ScheduleDTO] {
        schedules.map { toDTO($0) }
    }

    static func toDTOs(_ slots: [CDScheduleSlot]) -> [ScheduleSlotDTO] {
        slots.map { toDTO($0) }
    }

    static func toDTOs(_ issues: [CDIssue]) -> [IssueDTO] {
        issues.map { toDTO($0) }
    }

    static func toDTOs(_ actions: [IssueAction]) -> [IssueActionDTO] {
        actions.map { toDTO($0) }
    }

    static func toDTOs(_ snapshots: [DevelopmentSnapshot]) -> [DevelopmentSnapshotDTO] {
        snapshots.map { toDTO($0) }
    }

    static func toDTOs(_ items: [CDTodoItem]) -> [TodoItemDTO] {
        items.map { toDTO($0) }
    }

    static func toDTOs(_ subtasks: [CDTodoSubtask]) -> [TodoSubtaskDTO] {
        subtasks.map { toDTO($0) }
    }

    static func toDTOs(_ templates: [CDTodoTemplate]) -> [TodoTemplateDTO] {
        templates.map { toDTO($0) }
    }

    static func toDTOs(_ orders: [CDTodayAgendaOrder]) -> [TodayAgendaOrderDTO] {
        orders.map { toDTO($0) }
    }

    // MARK: - PlanningRecommendation

    static func toDTO(_ r: PlanningRecommendation) -> PlanningRecommendationDTO {
        PlanningRecommendationDTO(
            id: r.id ?? UUID(),
            createdAt: r.createdAt ?? Date(),
            modifiedAt: r.modifiedAt ?? Date(),
            lessonID: r.lessonID,
            studentIDsData: r._studentIDsData,
            reasoning: r.reasoning,
            confidence: r.confidence,
            priority: Int(r.priority),
            subjectContext: r.subjectContext,
            groupContext: r.groupContext,
            planningSessionID: r.planningSessionID,
            depthLevel: r.depthLevel,
            decisionRaw: r.decisionRaw,
            decisionAt: r.decisionAt,
            teacherNote: r.teacherNote,
            outcomeRaw: r.outcomeRaw,
            outcomeRecordedAt: r.outcomeRecordedAt,
            presentationID: r.presentationID
        )
    }

    static func toDTOs(_ recommendations: [PlanningRecommendation]) -> [PlanningRecommendationDTO] {
        recommendations.map { toDTO($0) }
    }

    // MARK: - CDResource

    static func toDTO(_ r: CDResource) -> ResourceDTO {
        ResourceDTO(
            id: r.id ?? UUID(),
            title: r.title,
            descriptionText: r.descriptionText,
            categoryRaw: r.categoryRaw,
            fileRelativePath: r.fileRelativePath,
            fileSizeBytes: r.fileSizeBytes,
            tags: (r.tags as? [String]) ?? [],
            isFavorite: r.isFavorite,
            lastViewedAt: r.lastViewedAt,
            linkedLessonIDs: r.linkedLessonIDs,
            linkedSubjects: r.linkedSubjects,
            createdAt: r.createdAt ?? Date(),
            modifiedAt: r.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ resources: [CDResource]) -> [ResourceDTO] {
        resources.map { toDTO($0) }
    }

    // MARK: - CDNoteStudentLink

    static func toDTO(_ link: CDNoteStudentLink) -> NoteStudentLinkDTO {
        NoteStudentLinkDTO(
            id: link.id ?? UUID(),
            noteID: link.noteID,
            studentID: link.studentID
        )
    }

    static func toDTOs(_ links: [CDNoteStudentLink]) -> [NoteStudentLinkDTO] {
        links.map { toDTO($0) }
    }

    // MARK: - CDGoingOut

    static func toDTO(_ g: CDGoingOut) -> GoingOutDTO {
        GoingOutDTO(
            id: g.id ?? UUID(),
            createdAt: g.createdAt ?? Date(),
            modifiedAt: g.modifiedAt ?? Date(),
            title: g.title,
            purpose: g.purpose,
            destination: g.destination,
            proposedDate: g.proposedDate,
            actualDate: g.actualDate,
            statusRaw: g.statusRaw,
            studentIDs: (g.studentIDs as? [String]) ?? [],
            curriculumLinkIDs: g.curriculumLinkIDs,
            permissionStatusRaw: g.permissionStatusRaw,
            notes: g.notes,
            followUpWork: g.followUpWork,
            supervisorName: g.supervisorName
        )
    }

    static func toDTOs(_ goingOuts: [CDGoingOut]) -> [GoingOutDTO] {
        goingOuts.map { toDTO($0) }
    }

    // MARK: - GoingOutChecklistItem

    static func toDTO(_ item: GoingOutChecklistItem) -> GoingOutChecklistItemDTO {
        GoingOutChecklistItemDTO(
            id: item.id ?? UUID(),
            createdAt: item.createdAt ?? Date(),
            goingOutID: item.goingOutID,
            title: item.title,
            isCompleted: item.isCompleted,
            sortOrder: Int(item.sortOrder),
            assignedToStudentID: item.assignedToStudentID
        )
    }

    static func toDTOs(_ items: [GoingOutChecklistItem]) -> [GoingOutChecklistItemDTO] {
        items.map { toDTO($0) }
    }

    // MARK: - CDClassroomJob

    static func toDTO(_ job: CDClassroomJob) -> ClassroomJobDTO {
        ClassroomJobDTO(
            id: job.id ?? UUID(),
            createdAt: job.createdAt ?? Date(),
            modifiedAt: job.modifiedAt ?? Date(),
            name: job.name,
            jobDescription: job.jobDescription,
            icon: job.icon,
            colorRaw: job.colorRaw,
            sortOrder: Int(job.sortOrder),
            isActive: job.isActive,
            maxStudents: Int(job.maxStudents)
        )
    }

    static func toDTOs(_ jobs: [CDClassroomJob]) -> [ClassroomJobDTO] {
        jobs.map { toDTO($0) }
    }

    // MARK: - CDJobAssignment

    static func toDTO(_ a: CDJobAssignment) -> JobAssignmentDTO {
        JobAssignmentDTO(
            id: a.id ?? UUID(),
            createdAt: a.createdAt ?? Date(),
            modifiedAt: a.modifiedAt ?? Date(),
            jobID: a.jobID,
            studentID: a.studentID,
            weekStartDate: a.weekStartDate ?? Date(),
            isCompleted: a.isCompleted
        )
    }

    static func toDTOs(_ assignments: [CDJobAssignment]) -> [JobAssignmentDTO] {
        assignments.map { toDTO($0) }
    }

    // MARK: - CDTransitionPlan

    static func toDTO(_ plan: CDTransitionPlan) -> TransitionPlanDTO {
        TransitionPlanDTO(
            id: plan.id ?? UUID(),
            createdAt: plan.createdAt ?? Date(),
            modifiedAt: plan.modifiedAt ?? Date(),
            studentID: plan.studentID,
            fromLevelRaw: plan.fromLevelRaw,
            toLevelRaw: plan.toLevelRaw,
            statusRaw: plan.statusRaw,
            targetDate: plan.targetDate,
            notes: plan.notes
        )
    }

    static func toDTOs(_ plans: [CDTransitionPlan]) -> [TransitionPlanDTO] {
        plans.map { toDTO($0) }
    }

    // MARK: - TransitionChecklistItem

    static func toDTO(_ item: TransitionChecklistItem) -> TransitionChecklistItemDTO {
        TransitionChecklistItemDTO(
            id: item.id ?? UUID(),
            createdAt: item.createdAt ?? Date(),
            transitionPlanID: item.transitionPlanID,
            title: item.title,
            categoryRaw: item.categoryRaw,
            isCompleted: item.isCompleted,
            completedAt: item.completedAt,
            sortOrder: Int(item.sortOrder),
            notes: item.notes
        )
    }

    static func toDTOs(_ items: [TransitionChecklistItem]) -> [TransitionChecklistItemDTO] {
        items.map { toDTO($0) }
    }

    // MARK: - CDCalendarNote

    static func toDTO(_ note: CDCalendarNote) -> CalendarNoteDTO {
        CalendarNoteDTO(
            id: note.id ?? UUID(),
            year: Int(note.year),
            month: Int(note.month),
            day: Int(note.day),
            text: note.text,
            createdAt: note.createdAt ?? Date(),
            modifiedAt: note.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ notes: [CDCalendarNote]) -> [CalendarNoteDTO] {
        notes.map { toDTO($0) }
    }

    // MARK: - CDScheduledMeeting

    static func toDTO(_ meeting: CDScheduledMeeting) -> ScheduledMeetingDTO {
        ScheduledMeetingDTO(
            id: meeting.id ?? UUID(),
            studentID: meeting.studentID,
            date: meeting.date ?? Date(),
            createdAt: meeting.createdAt ?? Date()
        )
    }

    static func toDTOs(_ meetings: [CDScheduledMeeting]) -> [ScheduledMeetingDTO] {
        meetings.map { toDTO($0) }
    }

    // MARK: - AlbumGroupOrder

    static func toDTO(_ order: AlbumGroupOrder) -> AlbumGroupOrderDTO {
        AlbumGroupOrderDTO(
            id: order.id ?? UUID(),
            scopeKey: order.scopeKey ?? "",
            groupName: order.groupName ?? "",
            sortIndex: Int(order.sortIndex)
        )
    }

    static func toDTOs(_ orders: [AlbumGroupOrder]) -> [AlbumGroupOrderDTO] {
        orders.map { toDTO($0) }
    }

    // MARK: - AlbumGroupUIState

    static func toDTO(_ state: AlbumGroupUIState) -> AlbumGroupUIStateDTO {
        AlbumGroupUIStateDTO(
            id: state.id ?? UUID(),
            scopeKey: state.scopeKey ?? "",
            groupName: state.groupName ?? "",
            isCollapsed: state.isCollapsed
        )
    }

    static func toDTOs(_ states: [AlbumGroupUIState]) -> [AlbumGroupUIStateDTO] {
        states.map { toDTO($0) }
    }
}
