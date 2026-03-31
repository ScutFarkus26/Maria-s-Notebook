import Foundation
import CoreData
import OSLog

// MARK: - Calendar/CDSchedule Imports

extension BackupEntityImporter {
    private static let logger = Logger.backup

    // MARK: - Non-School Days

    /// Imports non-school days from DTOs.
    static func importNonSchoolDays(
        _ dtos: [NonSchoolDayDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDNonSchoolDay>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let day = CDNonSchoolDay(context: viewContext)
            day.id = dto.id
            day.date = dto.date
            day.reason = dto.reason
            return day
        })
    }

    // MARK: - School Day Overrides

    /// Imports school day overrides from DTOs.
    static func importSchoolDayOverrides(
        _ dtos: [SchoolDayOverrideDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDSchoolDayOverride>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let override = CDSchoolDayOverride(context: viewContext)
            override.id = dto.id
            override.date = dto.date
            return override
        })
    }

    // MARK: - Schedules

    static func importSchedules(
        _ dtos: [ScheduleDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDSchedule>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let s = CDSchedule(context: viewContext)
            s.id = dto.id
            s.name = dto.name
            s.notes = dto.notes
            s.colorHex = dto.colorHex
            s.icon = dto.icon
            s.createdAt = dto.createdAt
            s.modifiedAt = dto.modifiedAt
            return s
        })
    }

    // MARK: - CDSchedule Slots

    static func importScheduleSlots(
        _ dtos: [ScheduleSlotDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDScheduleSlot>,
        scheduleCheck: EntityExistsCheck<CDSchedule>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let slot = CDScheduleSlot(context: viewContext)
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
