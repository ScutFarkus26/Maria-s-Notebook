import Foundation
import SwiftData
import OSLog

// MARK: - GoingOut, ClassroomJob, TransitionPlan, CalendarNote, ScheduledMeeting, AlbumGroup entities

extension BackupEntityImporter {

    // MARK: - GoingOut

    static func importGoingOuts(
        _ dtos: [GoingOutDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<GoingOut>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let g = GoingOut(
                id: dto.id,
                title: dto.title,
                purpose: dto.purpose,
                destination: dto.destination,
                proposedDate: dto.proposedDate,
                statusRaw: dto.statusRaw,
                studentIDs: dto.studentIDs,
                curriculumLinkIDs: dto.curriculumLinkIDs,
                permissionStatusRaw: dto.permissionStatusRaw,
                notes: dto.notes,
                followUpWork: dto.followUpWork,
                supervisorName: dto.supervisorName
            )
            g.createdAt = dto.createdAt
            g.modifiedAt = dto.modifiedAt
            g.actualDate = dto.actualDate
            return g
        })
    }

    // MARK: - GoingOutChecklistItem

    static func importGoingOutChecklistItems(
        _ dtos: [GoingOutChecklistItemDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<GoingOutChecklistItem>,
        goingOutCheck: EntityExistsCheck<GoingOut>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let goingOutUUID = UUID(uuidString: dto.goingOutID) else { continue }
            let item = GoingOutChecklistItem(
                id: dto.id,
                goingOutID: goingOutUUID,
                title: dto.title,
                isCompleted: dto.isCompleted,
                sortOrder: dto.sortOrder,
                assignedToStudentID: dto.assignedToStudentID.flatMap { UUID(uuidString: $0) }
            )
            item.createdAt = dto.createdAt
            do {
                if let goingOut = try goingOutCheck(goingOutUUID) {
                    item.goingOut = goingOut
                }
            } catch {
                Logger.backup.warning(
                    "Failed to check goingOut for checklist item: \(error.localizedDescription, privacy: .public)"
                )
            }
            modelContext.insert(item)
        }
    }

    // MARK: - ClassroomJob

    static func importClassroomJobs(
        _ dtos: [ClassroomJobDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ClassroomJob>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let job = ClassroomJob(
                id: dto.id,
                name: dto.name,
                jobDescription: dto.jobDescription,
                icon: dto.icon,
                colorRaw: dto.colorRaw,
                sortOrder: dto.sortOrder,
                isActive: dto.isActive,
                maxStudents: dto.maxStudents
            )
            job.createdAt = dto.createdAt
            job.modifiedAt = dto.modifiedAt
            return job
        })
    }

    // MARK: - JobAssignment

    static func importJobAssignments(
        _ dtos: [JobAssignmentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<JobAssignment>,
        jobCheck: EntityExistsCheck<ClassroomJob>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let a = JobAssignment(
                id: dto.id,
                jobID: dto.jobID,
                studentID: dto.studentID,
                weekStartDate: dto.weekStartDate,
                isCompleted: dto.isCompleted
            )
            a.createdAt = dto.createdAt
            a.modifiedAt = dto.modifiedAt
            if let jobUUID = UUID(uuidString: dto.jobID) {
                do {
                    if let job = try jobCheck(jobUUID) {
                        a.job = job
                    }
                } catch {
                    Logger.backup.warning(
                        "Failed to check job for assignment: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            modelContext.insert(a)
        }
    }

    // MARK: - TransitionPlan

    static func importTransitionPlans(
        _ dtos: [TransitionPlanDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<TransitionPlan>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let plan = TransitionPlan(
                id: dto.id,
                studentID: dto.studentID,
                fromLevelRaw: dto.fromLevelRaw,
                toLevelRaw: dto.toLevelRaw,
                status: TransitionStatus(rawValue: dto.statusRaw) ?? .notStarted,
                targetDate: dto.targetDate,
                notes: dto.notes
            )
            plan.createdAt = dto.createdAt
            plan.modifiedAt = dto.modifiedAt
            return plan
        })
    }

    // MARK: - TransitionChecklistItem

    static func importTransitionChecklistItems(
        _ dtos: [TransitionChecklistItemDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<TransitionChecklistItem>,
        planCheck: EntityExistsCheck<TransitionPlan>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let item = TransitionChecklistItem(
                id: dto.id,
                transitionPlanID: dto.transitionPlanID,
                title: dto.title,
                category: ChecklistCategory(rawValue: dto.categoryRaw) ?? .academic,
                sortOrder: dto.sortOrder
            )
            item.createdAt = dto.createdAt
            item.isCompleted = dto.isCompleted
            item.completedAt = dto.completedAt
            item.notes = dto.notes
            if let planUUID = UUID(uuidString: dto.transitionPlanID) {
                do {
                    if let plan = try planCheck(planUUID) {
                        item.transitionPlan = plan
                    }
                } catch {
                    Logger.backup.warning(
                        "Failed to check plan for checklist item: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            modelContext.insert(item)
        }
    }

    // MARK: - CalendarNote

    static func importCalendarNotes(
        _ dtos: [CalendarNoteDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<CalendarNote>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let note = CalendarNote(year: dto.year, month: dto.month, day: dto.day, text: dto.text)
            note.id = dto.id
            note.createdAt = dto.createdAt
            note.modifiedAt = dto.modifiedAt
            return note
        })
    }

    // MARK: - ScheduledMeeting

    static func importScheduledMeetings(
        _ dtos: [ScheduledMeetingDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ScheduledMeeting>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let studentUUID = UUID(uuidString: dto.studentID) else { continue }
            let meeting = ScheduledMeeting(
                id: dto.id,
                studentID: studentUUID,
                date: dto.date
            )
            meeting.createdAt = dto.createdAt
            modelContext.insert(meeting)
        }
    }

    // MARK: - AlbumGroupOrder

    static func importAlbumGroupOrders(
        _ dtos: [AlbumGroupOrderDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<AlbumGroupOrder>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            AlbumGroupOrder(
                id: dto.id,
                scopeKey: dto.scopeKey,
                groupName: dto.groupName,
                sortIndex: dto.sortIndex
            )
        })
    }

    // MARK: - AlbumGroupUIState

    static func importAlbumGroupUIStates(
        _ dtos: [AlbumGroupUIStateDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<AlbumGroupUIState>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            AlbumGroupUIState(
                id: dto.id,
                scopeKey: dto.scopeKey,
                groupName: dto.groupName,
                isCollapsed: dto.isCollapsed
            )
        })
    }
}
