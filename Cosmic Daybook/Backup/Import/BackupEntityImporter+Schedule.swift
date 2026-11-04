import Foundation
import CoreData
import OSLog

// MARK: - CDSchedule Imports

extension BackupEntityImporter {
    private static let logger = Logger.backup

    // MARK: - CDSchedule Slots

    static func importScheduleSlots(
        _ dtos: [ScheduleSlotDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDScheduleSlot>,
        scheduleCheck: EntityLookup<CDSchedule>
    ) rethrows {
        for dto in dtos {
            let slot = existingEntity(id: dto.id, existing: existing) ?? CDScheduleSlot(context: viewContext)
            slot.id = dto.id
            slot.scheduleID = dto.scheduleID
            slot.studentID = dto.studentID
            slot.weekdayRaw = (Weekday(rawValue: dto.weekdayRaw) ?? .monday).rawValue
            slot.timeString = dto.timeString
            slot.sortOrder = Int64(dto.sortOrder)
            slot.notes = dto.notes
            slot.createdAt = dto.createdAt
            slot.modifiedAt = dto.modifiedAt
            if let scheduleUUID = UUID(uuidString: dto.scheduleID) {
                do {
                    if let schedule = try scheduleCheck(scheduleUUID) {
                        slot.schedule = schedule
                    }
                } catch {
                    let desc = error.localizedDescription
                    Self.logger.warning("Failed to check schedule for slot: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(slot)
        }
    }
}
