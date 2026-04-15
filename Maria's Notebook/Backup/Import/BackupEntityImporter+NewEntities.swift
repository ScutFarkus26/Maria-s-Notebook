import Foundation
import CoreData
import OSLog

// MARK: - CDGoingOut, CDClassroomJob, CDTransitionPlan, CDCalendarNote, CDScheduledMeeting, AlbumGroup entities

extension BackupEntityImporter {

    // MARK: - CDGoingOut

    static func importGoingOuts(
        _ dtos: [GoingOutDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDGoingOut>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let g = CDGoingOut(context: viewContext)
            g.id = dto.id
            g.title = dto.title
            g.purpose = dto.purpose
            g.destination = dto.destination
            g.proposedDate = dto.proposedDate
            g.statusRaw = dto.statusRaw
            g.studentIDs = dto.studentIDs as NSObject
            g.curriculumLinkIDs = dto.curriculumLinkIDs
            g.permissionStatusRaw = dto.permissionStatusRaw
            g.notes = dto.notes
            g.followUpWork = dto.followUpWork
            g.supervisorName = dto.supervisorName
            g.createdAt = dto.createdAt
            g.modifiedAt = dto.modifiedAt
            g.actualDate = dto.actualDate
            return g
        })
    }

    // MARK: - CDGoingOutChecklistItem

    static func importGoingOutChecklistItems(
        _ dtos: [GoingOutChecklistItemDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDGoingOutChecklistItem>,
        goingOutCheck: EntityExistsCheck<CDGoingOut>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let goingOutUUID = UUID(uuidString: dto.goingOutID) else { continue }
            let item = CDGoingOutChecklistItem(context: viewContext)
            item.id = dto.id
            item.goingOutID = goingOutUUID.uuidString
            item.title = dto.title
            item.isCompleted = dto.isCompleted
            item.sortOrder = Int64(dto.sortOrder)
            item.assignedToStudentID = dto.assignedToStudentID
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
            viewContext.insert(item)
        }
    }

    // MARK: - CDClassroomJob

    static func importClassroomJobs(
        _ dtos: [ClassroomJobDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDClassroomJob>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let job = CDClassroomJob(context: viewContext)
            job.id = dto.id
            job.name = dto.name
            job.jobDescription = dto.jobDescription
            job.icon = dto.icon
            job.colorRaw = dto.colorRaw
            job.sortOrder = Int64(dto.sortOrder)
            job.isActive = dto.isActive
            job.maxStudents = Int64(dto.maxStudents)
            job.createdAt = dto.createdAt
            job.modifiedAt = dto.modifiedAt
            return job
        })
    }

    // MARK: - CDJobAssignment

    static func importJobAssignments(
        _ dtos: [JobAssignmentDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDJobAssignment>,
        jobCheck: EntityExistsCheck<CDClassroomJob>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let a = CDJobAssignment(context: viewContext)
            a.id = dto.id
            a.jobID = dto.jobID
            a.studentID = dto.studentID
            a.weekStartDate = dto.weekStartDate
            a.isCompleted = dto.isCompleted
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
            viewContext.insert(a)
        }
    }

    // MARK: - CDTransitionPlan

    static func importTransitionPlans(
        _ dtos: [TransitionPlanDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDTransitionPlan>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let plan = CDTransitionPlan(context: viewContext)
            plan.id = dto.id
            plan.studentID = dto.studentID
            plan.fromLevelRaw = dto.fromLevelRaw
            plan.toLevelRaw = dto.toLevelRaw
            plan.statusRaw = (TransitionStatus(rawValue: dto.statusRaw) ?? .notStarted).rawValue
            plan.targetDate = dto.targetDate
            plan.notes = dto.notes
            plan.createdAt = dto.createdAt
            plan.modifiedAt = dto.modifiedAt
            return plan
        })
    }

    // MARK: - CDTransitionChecklistItem

    static func importTransitionChecklistItems(
        _ dtos: [TransitionChecklistItemDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDTransitionChecklistItem>,
        planCheck: EntityExistsCheck<CDTransitionPlan>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let item = CDTransitionChecklistItem(context: viewContext)
            item.id = dto.id
            item.transitionPlanID = dto.transitionPlanID
            item.title = dto.title
            item.categoryRaw = (ChecklistCategory(rawValue: dto.categoryRaw) ?? .academic).rawValue
            item.sortOrder = Int64(dto.sortOrder)
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
            viewContext.insert(item)
        }
    }

    // MARK: - CDCalendarNote

    static func importCalendarNotes(
        _ dtos: [CalendarNoteDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDCalendarNote>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let note = CDCalendarNote(context: viewContext)
            note.id = dto.id
            note.year = Int64(dto.year)
            note.month = Int64(dto.month)
            note.day = Int64(dto.day)
            note.text = dto.text
            note.createdAt = dto.createdAt
            note.modifiedAt = dto.modifiedAt
            return note
        })
    }

    // MARK: - CDScheduledMeeting

    static func importScheduledMeetings(
        _ dtos: [ScheduledMeetingDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDScheduledMeeting>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let studentUUID = UUID(uuidString: dto.studentID) else { continue }
            let meeting = CDScheduledMeeting(context: viewContext)
            meeting.id = dto.id
            meeting.studentID = studentUUID.uuidString
            meeting.date = dto.date
            meeting.createdAt = dto.createdAt
            meeting._participantIDsData = dto.participantIDsData
            meeting.workID = dto.workID
            meeting.isGroupMeeting = dto.isGroupMeeting ?? false
            viewContext.insert(meeting)
        }
    }

    // MARK: - AlbumGroupOrder
    // No-op: AlbumGroupOrder has no entity in the .xcdatamodeld (legacy SwiftData stub).
    // DTOs are decoded from old backups but silently dropped during import.

    static func importAlbumGroupOrders(
        _ dtos: [AlbumGroupOrderDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<AlbumGroupOrder>
    ) rethrows {
        // Intentionally empty — entity does not exist in Core Data model
    }

    // MARK: - AlbumGroupUIState
    // No-op: AlbumGroupUIState has no entity in the .xcdatamodeld (legacy SwiftData stub).

    static func importAlbumGroupUIStates(
        _ dtos: [AlbumGroupUIStateDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<AlbumGroupUIState>
    ) rethrows {
        // Intentionally empty — entity does not exist in Core Data model
    }

    // MARK: - CDClassroomMembership (format v13+)

    static func importClassroomMemberships(
        _ dtos: [ClassroomMembershipDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDClassroomMembership>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let membership = CDClassroomMembership(context: viewContext)
            membership.id = dto.id
            membership.classroomZoneID = dto.classroomZoneID
            membership.roleRaw = dto.roleRaw
            membership.ownerIdentity = dto.ownerIdentity
            membership.joinedAt = dto.joinedAt
            membership.modifiedAt = dto.modifiedAt
            return membership
        })
    }

    // MARK: - CDMeetingWorkReview (format v14+)

    static func importMeetingWorkReviews(
        _ dtos: [MeetingWorkReviewDTO],
        into viewContext: NSManagedObjectContext
    ) {
        for dto in dtos {
            let entity = CDMeetingWorkReview(context: viewContext)
            entity.id = dto.id
            entity.meetingID = dto.meetingID
            entity.workID = dto.workID
            entity.noteText = dto.noteText
            entity.createdAt = dto.createdAt

            // Wire relationship
            let request = NSFetchRequest<CDStudentMeeting>(entityName: "StudentMeeting")
            request.predicate = NSPredicate(format: "id == %@", (UUID(uuidString: dto.meetingID) ?? UUID()) as CVarArg)
            request.fetchLimit = 1
            entity.meeting = try? viewContext.fetch(request).first
        }
    }

    // MARK: - CDStudentFocusItem (format v14+)

    static func importStudentFocusItems(
        _ dtos: [StudentFocusItemDTO],
        into viewContext: NSManagedObjectContext
    ) {
        for dto in dtos {
            let entity = CDStudentFocusItem(context: viewContext)
            entity.id = dto.id
            entity.studentID = dto.studentID
            entity.text = dto.text
            entity.statusRaw = dto.statusRaw
            entity.createdInMeetingID = dto.createdInMeetingID
            entity.resolvedInMeetingID = dto.resolvedInMeetingID
            entity.resolvedAt = dto.resolvedAt
            entity.createdAt = dto.createdAt
            entity.sortOrder = Int64(dto.sortOrder)
        }
    }
}
