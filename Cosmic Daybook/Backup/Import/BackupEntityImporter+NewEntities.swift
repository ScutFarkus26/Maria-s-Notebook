import Foundation
import CoreData
import OSLog

// MARK: - CDGoingOut, CDClassroomJob, CDCalendarNote, CDScheduledMeeting

extension BackupEntityImporter {

    // MARK: - CDGoingOutChecklistItem

    static func importGoingOutChecklistItems(
        _ dtos: [GoingOutChecklistItemDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDGoingOutChecklistItem>,
        goingOutCheck: EntityLookup<CDGoingOut>
    ) rethrows {
        for dto in dtos {
            guard let goingOutUUID = UUID(uuidString: dto.goingOutID) else { continue }
            let item = existingEntity(id: dto.id, existing: existing) ?? CDGoingOutChecklistItem(context: viewContext)
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

    // MARK: - CDScheduledMeeting

    static func importScheduledMeetings(
        _ dtos: [ScheduledMeetingDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDScheduledMeeting>
    ) rethrows {
        for dto in dtos {
            guard let studentUUID = UUID(uuidString: dto.studentID) else { continue }
            let meeting = existingEntity(id: dto.id, existing: existing) ?? CDScheduledMeeting(context: viewContext)
            meeting.id = dto.id
            meeting.studentID = studentUUID.uuidString
            meeting.date = dto.date
            meeting.createdAt = dto.createdAt
            meeting._participantIDsData = dto.participantIDsData
            meeting.workID = dto.workID
            meeting.isGroupMeeting = dto.isGroupMeeting ?? false
            meeting.purpose = dto.purpose
            viewContext.insert(meeting)
        }
    }

}
