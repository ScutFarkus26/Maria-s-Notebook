import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The parts of R4 (the due date and the next check) and R11 (the check
// happened) that call what the fix added, so they couldn't run on main: the
// seen-since-due rule, the old copy of the check day, and the work page's Done.

extension WorkRulesTests {

    @Test("A due date asks until the work is seen; an old copy of the check day goes with its check")
    func dueDateAndTheOldCopy() throws {
        let today = day(0)
        let overdue = WorkTriageInput(status: .active, dueAt: day(-2))
        #expect(LessonsAndWorkTriage.bucket(for: overdue, asOf: today) == .attention)
        var seen = overdue
        seen.lastSeen = day(-1)
        #expect(LessonsAndWorkTriage.bucket(for: seen, asOf: today) == .toSchedule)
        seen.lastSeen = day(-5)
        #expect(LessonsAndWorkTriage.bucket(for: seen, asOf: today) == .attention, "seen before it came due")
        #expect(LessonsAndWorkTriage.bucket(for: WorkTriageInput(status: .active, dueAt: day(4)), asOf: today)
            == .scheduled)

        // An older build copied the check day into the due date. Clear All
        // takes the check off the calendar; the copy mustn't keep the work
        // out of To Schedule.
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame")
        CDWorkCheckIn.make(for: work, on: day(3), in: context)
        work.dueAt = day(3)
        let real = CoreDataTestHelpers.seedWorkModel(in: context, title: "Poster")
        CDWorkCheckIn.make(for: real, on: day(3), in: context)
        real.dueAt = day(9)
        #expect(CoreDataTestHelpers.save(context))

        CalendarClearAllService.clearAll(in: context)

        #expect(work.dueAt == nil)
        #expect(LessonsAndWorkTriage.bucket(for: work, context: context) == .toSchedule)
        #expect(real.dueAt == day(9), "a due date the guide set stays")
    }

    @Test("A Due Date check carries the due date with it, as a project follow-up's always has")
    func dueDateCheckCarriesTheDueDate() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        // A project follow-up keeps its due day on the work and on a Due Date
        // check-in (`SessionWorkAssignmentService.createUniformWork`).
        let project = CoreDataTestHelpers.seedWorkModel(in: context, title: "Poster")
        project.dueAt = day(3)
        CDWorkCheckIn.make(for: project, on: day(3), purpose: CheckInReason.dueDate.purpose, in: context)
        #expect(CoreDataTestHelpers.save(context))

        WorkCheckInService(context: context).scheduleCheck(for: project, on: day(5))
        #expect(project.dueAt == day(5), "the check is the due date, so the two move together")

        CalendarForwardShiftService.moveForwardOneDay(
            in: context, calendar: AppCalendar.shared, from: day(5),
            nextSchoolDay: { AppCalendar.addingDays(1, to: $0) }
        )
        #expect(WorkCheckInService.nextCheckDay(of: project, in: context) == day(6))
        #expect(project.dueAt == day(6))
    }

    @Test("Done on the work page settles Monday's missed check, and Undo puts the day back")
    func checkedCheckInSettlesEarlierOnesAndUndoes() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame")
        work.id = UUID()
        let missed = CDWorkCheckIn.make(for: work, on: day(-2), in: context)
        let planned = day(2)
        let ahead = CDWorkCheckIn.make(for: work, on: planned, in: context)
        #expect(CoreDataTestHelpers.save(context))

        // The work page's Done on Wednesday's check-in, tapped today.
        let receipt = try WorkLogService.log([.init(work: work)], checked: ahead, context: context)

        #expect(ahead.status == .completed)
        #expect(AppCalendar.isSameDay(try #require(ahead.date), Date()), "dated the day it was checked")
        #expect(missed.status == .completed)
        #expect(missed.date == day(-2), "a settled check-in keeps its day")
        #expect(work.lastTouchedAt != nil)
        #expect(work.status == .active, "seen, unchanged")
        #expect(LessonsAndWorkTriage.bucket(for: work, context: context) != .attention)

        try WorkLogService.undo(receipt.token, context: context)

        #expect(ahead.status == .scheduled)
        #expect(ahead.date == planned)
        #expect(missed.status == .scheduled)
    }
}
