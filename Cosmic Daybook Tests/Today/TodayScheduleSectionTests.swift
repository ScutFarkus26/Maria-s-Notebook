import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Simplify the app, Phase 7: Schedules feeds Today. The day's slots on the
/// recurring schedules show on Today, grouped by schedule, read once per
/// reload; the section's gate is pinned in `TodaySectionVisibilityTests`.
@Suite("Today's Schedule section")
@MainActor
struct TodayScheduleSectionTests {

    /// Sunday 18 October 2026, then the week after it.
    private func day(_ offset: Int) throws -> Date {
        try #require(AppCalendar.shared.date(from: DateComponents(year: 2026, month: 10, day: 18 + offset, hour: 10)))
    }

    private func schedule(_ name: String, in context: NSManagedObjectContext) -> CDSchedule {
        let schedule = CDSchedule(context: context)
        schedule.name = name
        schedule.icon = "book"
        return schedule
    }

    @discardableResult
    private func slot(
        _ studentID: UUID?, on weekday: Weekday, at time: String?, notes: String = "",
        of schedule: CDSchedule, in context: NSManagedObjectContext
    ) -> CDScheduleSlot {
        let slot = CDScheduleSlot(context: context)
        slot.scheduleID = schedule.id?.uuidString ?? ""
        slot.studentID = studentID?.uuidString ?? ""
        slot.weekday = weekday
        slot.timeString = time
        slot.notes = notes
        slot.schedule = schedule
        return slot
    }

    // MARK: - Weekday(date:)

    @Test("Weekday(date:) names the day of the week a date falls on")
    func weekdayFromDate() throws {
        let week: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        for (offset, expected) in week.enumerated() {
            #expect(Weekday(date: try day(offset)) == expected)
        }
        // Late in the evening is still that day in the calendar given.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let mondayNight = try #require(newYork.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 23)))
        #expect(Weekday(date: mondayNight, calendar: newYork) == .monday)
    }

    // MARK: - Groups

    @Test("The day's slots, by schedule name and then time; children who left, other days and empty schedules stay off")
    func groupsTheDaysSlots() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto", level: .upper)
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Ross", level: .lower)
        let gone = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Leah", lastName: "Gold", enrollmentStatus: .withdrawn
        )
        let speech = schedule("Speech", in: context)
        let reading = schedule("Reading support", in: context)
        let tuesdaysOnly = schedule("Art club", in: context)
        slot(maya.id, on: .monday, at: "1:15", of: reading, in: context)
        slot(eli.id, on: .monday, at: "9:30", notes: "Bring the bead chains", of: reading, in: context)
        slot(gone.id, on: .monday, at: "10:00", of: reading, in: context)
        slot(UUID(), on: .monday, at: "11:00", of: reading, in: context)
        slot(maya.id, on: .tuesday, at: "9:00", of: reading, in: context)
        slot(eli.id, on: .monday, at: nil, of: speech, in: context)
        slot(maya.id, on: .tuesday, at: "2:00", of: tuesdaysOnly, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let enrolled = Dictionary(uniqueKeysWithValues: [maya, eli].map { ($0.id!, $0) })

        let fetched = TodayScheduleSlots.fetch(weekday: .monday, context: context)
        #expect(fetched.neededStudentIDs.isSuperset(of: [maya.id!, eli.id!, gone.id!]))
        let groups = TodayScheduleSlots.groups(fetched, studentsByID: enrolled, levelFilter: .all)

        #expect(groups.map(\.name) == ["Reading support", "Speech"])
        let readingSlots = try #require(groups.first).slots
        #expect(readingSlots.map(\.studentName) == ["Eli R", "Maya S"])
        #expect(readingSlots.map(\.time) == ["9:30", "1:15"])
        #expect(readingSlots.first?.notes == "Bring the bead chains")
        #expect(readingSlots.last?.notes == nil)
        #expect(groups.last?.slots.map(\.time) == [nil])

        let upper = TodayScheduleSlots.groups(fetched, studentsByID: enrolled, levelFilter: .upper)
        #expect(upper.map(\.name) == ["Reading support"])
        #expect(upper.first?.slots.map(\.studentName) == ["Maya S"])

        let sunday = TodayScheduleSlots.fetch(weekday: .sunday, context: context)
        #expect(TodayScheduleSlots.groups(sunday, studentsByID: enrolled, levelFilter: .all).isEmpty)
    }

    // MARK: - On Today

    @Test("Today's reload reads the day's slots, and a schedule edited elsewhere reloads Today")
    func todayReadsAndFollowsTheSchedules() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let reading = schedule("Reading support", in: context)
        slot(maya.id, on: .monday, at: "9:30", of: reading, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = TodayViewModel(context: context, date: try day(1))
        viewModel.reload()
        #expect(viewModel.scheduleGroups.map(\.name) == ["Reading support"])
        #expect(viewModel.scheduleGroups.first?.slots.map(\.studentName) == ["Maya S"])

        viewModel.date = try day(2)
        viewModel.reload()
        #expect(viewModel.scheduleGroups.isEmpty)

        // A child added to the Tuesday schedule in the Schedules screen (or on another device).
        let afterFirst = viewModel.reloadCount
        let scheduleID = reading.objectID
        let mayaID = try #require(maya.id)
        let other = stack.newBackgroundContext()
        other.performAndWait {
            guard let schedule = other.object(with: scheduleID) as? CDSchedule else { return }
            let slot = CDScheduleSlot(context: other)
            slot.studentID = mayaID.uuidString
            slot.weekday = .tuesday
            slot.schedule = schedule
            _ = other.safeSave()
        }
        viewModel.scheduleReloadIfInputsChanged()
        await viewModel.reloadTask?.value
        #expect(viewModel.reloadCount == afterFirst + 1)
        #expect(viewModel.scheduleGroups.first?.slots.map(\.studentName) == ["Maya S"])
    }
}
