import Foundation
import CoreData

// MARK: - Misc Transformers
// (Todo, CDTrackEntity, CDSupply, CDSchedule, CDIssue, CDProcedure, CDDocument, etc.)

extension BackupDTOTransformers {

    // MARK: - CDSequenceTrack

    static func toDTO(_ g: CDSequenceTrack) -> SequenceTrackDTO {
        SequenceTrackDTO(
            id: g.id ?? UUID(),
            area: g.area,
            sequence: g.sequence,
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
            // Read the string FK directly: `d.student` is a computed cross-store
            // accessor that fetches the student and returns nil when it can't be
            // resolved — which would silently drop the link from the backup.
            studentID: d.studentID.flatMap { UUID(uuidString: $0) },
            pdfFileRelativePath: d.pdfFileRelativePath.isEmpty ? nil : d.pdfFileRelativePath
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
            notes: s.notes,
            createdAt: s.createdAt ?? Date(),
            modifiedAt: s.modifiedAt ?? Date(),
            minimumThreshold: Int(s.minimumThreshold),
            unit: s.unit,
            levelRaw: s.levelRaw,
            sourceRaw: s.sourceRaw,
            urlString: s.urlString,
            levelChangedAt: s.levelChangedAt,
            levelChangedByID: s.levelChangedByID,
            levelChangedByName: s.levelChangedByName
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

    // MARK: - CDIssueAction

    static func toDTO(_ a: CDIssueAction) -> IssueActionDTO {
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

    // MARK: - CDDevelopmentSnapshotEntity

    static func toDTO(_ s: CDDevelopmentSnapshotEntity) -> DevelopmentSnapshotDTO {
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
            notifyOnExit: t.notifyOnExit,
            moodRaw: t.moodRaw,
            tideLink: t.tideLink
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

    static func toDTOs(_ sequenceTracks: [CDSequenceTrack]) -> [SequenceTrackDTO] {
        sequenceTracks.map { toDTO($0) }
    }

    static func toDTOs(_ documents: [CDDocument]) -> [DocumentDTO] {
        documents.map { toDTO($0) }
    }

    static func toDTOs(_ supplies: [CDSupply]) -> [SupplyDTO] {
        supplies.map { toDTO($0) }
    }

    static func toDTOs(_ procedures: [CDProcedure]) -> [ProcedureDTO] {
        procedures.map { toDTO($0) }
    }

    static func toDTOs(_ slots: [CDScheduleSlot]) -> [ScheduleSlotDTO] {
        slots.map { toDTO($0) }
    }

    static func toDTOs(_ issues: [CDIssue]) -> [IssueDTO] {
        issues.map { toDTO($0) }
    }

    static func toDTOs(_ actions: [CDIssueAction]) -> [IssueActionDTO] {
        actions.map { toDTO($0) }
    }

    static func toDTOs(_ snapshots: [CDDevelopmentSnapshotEntity]) -> [DevelopmentSnapshotDTO] {
        snapshots.map { toDTO($0) }
    }

    static func toDTOs(_ items: [CDTodoItem]) -> [TodoItemDTO] {
        items.map { toDTO($0) }
    }

    static func toDTOs(_ orders: [CDTodayAgendaOrder]) -> [TodayAgendaOrderDTO] {
        orders.map { toDTO($0) }
    }

    // MARK: - CDPlanningRecommendation

    static func toDTO(_ r: CDPlanningRecommendation) -> PlanningRecommendationDTO {
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

    static func toDTOs(_ recommendations: [CDPlanningRecommendation]) -> [PlanningRecommendationDTO] {
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
            linkedAreas: r.linkedAreas,
            createdAt: r.createdAt ?? Date(),
            modifiedAt: r.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ resources: [CDResource]) -> [ResourceDTO] {
        resources.map { toDTO($0) }
    }

    // MARK: - CDGoingOutChecklistItem

    static func toDTO(_ item: CDGoingOutChecklistItem) -> GoingOutChecklistItemDTO {
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

    static func toDTOs(_ items: [CDGoingOutChecklistItem]) -> [GoingOutChecklistItemDTO] {
        items.map { toDTO($0) }
    }
}
