// TodayScheduleSlots.swift
// The day's slots on the recurring schedules (Schedules feeds Today).

import CoreData
import Foundation

/// Who is on each recurring schedule (`CDSchedule`: reading support, speech,
/// and the like) on the day Today shows, grouped by schedule.
///
/// Read once per reload (`TodayViewModel.reload`), like the meetings: one
/// fetch of the schedules with their slots, then the day's slots each one
/// keeps in time order (`CDSchedule.slots(for:)`).
enum TodayScheduleSlots {

    /// One schedule's slots on the day.
    struct Group: Identifiable, Equatable {
        let id: NSManagedObjectID
        let name: String
        let icon: String
        let colorHex: String
        let slots: [Slot]
    }

    /// One child on a schedule, at a time if the schedule gives one.
    struct Slot: Identifiable, Equatable {
        let id: NSManagedObjectID
        let time: String?
        let studentName: String
        let notes: String?
    }

    /// What one fetch read: the schedules, by name, and the children their
    /// slots name on the day (for the student cache).
    struct Fetched {
        let weekday: Weekday
        let schedules: [CDSchedule]
        let neededStudentIDs: Set<UUID>
    }

    /// The schedules with someone on `weekday`, with their slots fetched alongside.
    static func fetch(weekday: Weekday, context: NSManagedObjectContext) -> Fetched {
        let request = CDFetchRequest(CDSchedule.self)
        request.predicate = NSPredicate(format: "ANY slots.weekdayRaw == %@", weekday.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDSchedule.name, ascending: true)]
        request.relationshipKeyPathsForPrefetching = ["slots"]
        let schedules = context.safeFetch(request).filter { !$0.isDeleted }
        let ids = schedules.flatMap { $0.slots(for: weekday) }.compactMap { UUID(uuidString: $0.studentID) }
        return Fetched(weekday: weekday, schedules: schedules, neededStudentIDs: Set(ids))
    }

    /// The day's groups: each schedule with a slot on the day for a child
    /// in `studentsByID` (enrolled and shown) who fits the level filter.
    /// A slot for a child who has left, or isn't in the notebook, isn't shown;
    /// a schedule with none left isn't either.
    static func groups(
        _ fetched: Fetched,
        studentsByID: [UUID: CDStudent],
        levelFilter: LevelFilter
    ) -> [Group] {
        fetched.schedules.compactMap { schedule in
            let slots = schedule.slots(for: fetched.weekday).compactMap { slot -> Slot? in
                guard let id = UUID(uuidString: slot.studentID),
                      let student = studentsByID[id],
                      levelFilter.matches(student.level) else { return nil }
                return Slot(
                    id: slot.objectID,
                    time: slot.timeString?.trimmed().nilIfEmpty,
                    studentName: student.shortName,
                    notes: slot.notes.trimmed().nilIfEmpty
                )
            }
            guard !slots.isEmpty else { return nil }
            let name = schedule.name.trimmed()
            return Group(
                id: schedule.objectID,
                name: name.isEmpty ? "Schedule" : name,
                icon: schedule.icon,
                colorHex: schedule.colorHex,
                slots: slots
            )
        }
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
