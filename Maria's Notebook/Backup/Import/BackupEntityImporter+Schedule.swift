import Foundation
import SwiftData

// MARK: - Calendar/Schedule Imports

extension BackupEntityImporter {

    // MARK: - Non-School Days

    /// Imports non-school days from DTOs.
    static func importNonSchoolDays(
        _ dtos: [NonSchoolDayDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<NonSchoolDay>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let day = NonSchoolDay(id: dto.id, date: dto.date)
            day.reason = dto.reason
            return day
        })
    }

    // MARK: - School Day Overrides

    /// Imports school day overrides from DTOs.
    static func importSchoolDayOverrides(
        _ dtos: [SchoolDayOverrideDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<SchoolDayOverride>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let override = SchoolDayOverride(id: dto.id, date: dto.date)
            return override
        })
    }

    // MARK: - Schedules

    static func importSchedules(
        _ dtos: [ScheduleDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Schedule>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let s = Schedule(
                id: dto.id,
                name: dto.name,
                notes: dto.notes,
                colorHex: dto.colorHex,
                icon: dto.icon,
                createdAt: dto.createdAt,
                modifiedAt: dto.modifiedAt
            )
            return s
        })
    }

    // MARK: - Schedule Slots

    static func importScheduleSlots(
        _ dtos: [ScheduleSlotDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ScheduleSlot>,
        scheduleCheck: EntityExistsCheck<Schedule>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let slot = ScheduleSlot(
                id: dto.id,
                scheduleID: dto.scheduleID,
                studentID: dto.studentID,
                weekday: Weekday(rawValue: dto.weekdayRaw) ?? .monday,
                timeString: dto.timeString,
                sortOrder: dto.sortOrder,
                notes: dto.notes,
                createdAt: dto.createdAt,
                modifiedAt: dto.modifiedAt
            )
            if let scheduleUUID = UUID(uuidString: dto.scheduleID) {
                do {
                    if let schedule = try scheduleCheck(scheduleUUID) {
                        slot.schedule = schedule
                    }
                } catch {
                    print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check schedule for slot: \(error)")
                }
            }
            modelContext.insert(slot)
        }
    }
}
