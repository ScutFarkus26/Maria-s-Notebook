import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Schedules (bug hunt 2026-10-10, P2 #29, #30): an edit updates the slots in
/// place, and times sort as a school day reads them.
@Suite("Schedules: slots kept in place, times in day order")
@MainActor
struct ScheduleSlotFix1010Tests {

    private typealias Entry = ScheduleSlotWriter.Entry

    private static func slot(
        _ studentID: String, on weekday: Weekday, at time: String?, of schedule: CDSchedule,
        in context: NSManagedObjectContext
    ) -> CDScheduleSlot {
        let slot = CDScheduleSlot(context: context)
        slot.scheduleID = schedule.id?.uuidString ?? ""
        slot.studentID = studentID
        slot.weekday = weekday
        slot.timeString = time
        slot.schedule = schedule
        return slot
    }

    @Test("An edit keeps each child's slot, drops only the ones taken off, and adds the new ones")
    func editUpdatesSlotsInPlace() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let schedule = CDSchedule(context: context)
        schedule.name = "Reading support"
        let mayaMonday = Self.slot("maya", on: .monday, at: "9:30", of: schedule, in: context)
        let leoMonday = Self.slot("leo", on: .monday, at: "10:00", of: schedule, in: context)
        let mayaTuesday = Self.slot("maya", on: .tuesday, at: nil, of: schedule, in: context)
        #expect(context.safeSave())
        let keptID = mayaMonday.id

        let outcome = ScheduleSlotWriter.apply(
            [.monday: [Entry(studentID: "maya", timeString: "9:45"), Entry(studentID: "ora", timeString: "")]],
            to: schedule, in: context
        )
        #expect(outcome == ScheduleSlotWriter.Outcome(inserted: 1, updated: 1, deleted: 2))
        #expect(context.safeSave())

        #expect(!mayaMonday.isDeleted && mayaMonday.id == keptID)
        #expect(mayaMonday.timeString == "9:45")
        #expect(leoMonday.managedObjectContext == nil)
        #expect(mayaTuesday.managedObjectContext == nil)
        #expect(schedule.slots(for: .monday).map(\.studentID) == ["maya", "ora"])

        // Saving the same thing again writes nothing.
        let again = ScheduleSlotWriter.apply(
            [.monday: [Entry(studentID: "maya", timeString: "9:45"), Entry(studentID: "ora", timeString: "")]],
            to: schedule, in: context
        )
        #expect(again == ScheduleSlotWriter.Outcome())
        #expect(!context.hasChanges)
    }

    @Test("A child on one day twice keeps the slot made first; the extra goes")
    func duplicateSlotsFold() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let schedule = CDSchedule(context: context)
        let first = Self.slot("maya", on: .wednesday, at: "1:15", of: schedule, in: context)
        first.createdAt = Date(timeIntervalSince1970: 1_000)
        let second = Self.slot("maya", on: .wednesday, at: "1:15", of: schedule, in: context)
        second.createdAt = Date(timeIntervalSince1970: 2_000)
        #expect(context.safeSave())

        let outcome = ScheduleSlotWriter.apply(
            [.wednesday: [Entry(studentID: "maya", timeString: "1:15")]], to: schedule, in: context
        )
        #expect(outcome == ScheduleSlotWriter.Outcome(deleted: 1))
        #expect(!first.isDeleted)
        #expect(second.isDeleted)
    }

    @Test("Times sort as a school day reads them: 1:15 after 9:30, AM and PM understood, blanks last")
    func timesSortInDayOrder() {
        #expect(ScheduleTime.minutes("9:30") == 9 * 60 + 30)
        #expect(ScheduleTime.minutes("1:15") == 13 * 60 + 15)
        #expect(ScheduleTime.minutes("1:15 am") == 75)
        #expect(ScheduleTime.minutes("10:00 A.M.") == 600)
        #expect(ScheduleTime.minutes("12:30") == 12 * 60 + 30)
        #expect(ScheduleTime.minutes("12:05pm") == 12 * 60 + 5)
        #expect(ScheduleTime.minutes("12 am") == 0)
        #expect(ScheduleTime.minutes("2 PM") == 14 * 60)
        #expect(ScheduleTime.minutes("14:20") == 14 * 60 + 20)
        #expect(ScheduleTime.minutes("9:5") == nil)
        #expect(ScheduleTime.minutes("after lunch") == nil)

        let typed = ["", "1:15", "after lunch", "9:30", "2 pm", "10:00 AM", "12:30"]
        let entries = typed.map { Entry(studentID: $0, timeString: $0) }
        let order = ScheduleSlotWriter.ordered(entries).map(\.timeString)
        #expect(order == ["9:30", "10:00 AM", "12:30", "1:15", "2 pm", "after lunch", ""])
    }
}
