import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Scheduled strip's moves (bug hunt 2026-10-12): Reschedule › Tomorrow
/// on a pill lands on the next school day and names it (#48), and Move All
/// Forward moves the presentations the guide can see from today on and every
/// open work check (overdue ones to today, since 2026-10-13), gives each work
/// its earliest moved check-in as its due day, and can be taken back (#49).
@Suite("Presentations fixes 2026-10-12: the Scheduled strip")
@MainActor
struct WeekStripFix1012Pr {

    private func day(_ iso: String) throws -> Date {
        AppCalendar.startOfDay(try CoreDataTestHelpers.day(iso))
    }

    private func time(_ hour: Int, on base: Date) -> Date {
        AppCalendar.shared.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    /// Weekdays only, so the tests don't read the school-day cache.
    private func nextWeekday(after date: Date) -> Date {
        var cursor = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(date))
        while AppCalendar.shared.isDateInWeekend(cursor) {
            cursor = AppCalendar.addingDays(1, to: cursor)
        }
        return cursor
    }

    // MARK: - Reschedule › Tomorrow (#48)

    @Test("Tomorrow from a Friday is Monday, and the menu says so")
    func tomorrowFromFridayIsMonday() throws {
        let friday = try day("2026-10-16")
        let target = WorkCheckRescheduleDay.next(
            today: time(10, on: friday), calendar: AppCalendar.shared, nextSchoolDay: nextWeekday(after:)
        )
        #expect(target.day == (try day("2026-10-19")))
        #expect(target.title == "Monday")
    }

    @Test("Tomorrow midweek is the next day, called Tomorrow")
    func tomorrowMidweek() throws {
        let tuesday = try day("2026-10-13")
        let target = WorkCheckRescheduleDay.next(
            today: tuesday, calendar: AppCalendar.shared, nextSchoolDay: nextWeekday(after:)
        )
        #expect(target.day == (try day("2026-10-14")))
        #expect(target.title == "Tomorrow")
    }

    // MARK: - Logging a later pill (#37)

    @Test("A pill can be logged on its day or after, not before")
    func laterPillIsNotLogged() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let monday = try day("2026-10-12")
        func pill(on date: Date) -> CalendarCheckInGroup {
            let checkIn = CDWorkCheckIn(context: context)
            checkIn.date = date
            return CalendarCheckInGroup(
                id: UUID(), checkIns: [checkIn], lessonTitle: "Checkerboard",
                studentNames: ["Ora L"], purpose: "progressCheck", sortDate: date
            )
        }
        let today = time(15, on: monday)
        #expect(WorkCheckPillActions.canLog(pill(on: time(9, on: monday)), today: today))
        #expect(WorkCheckPillActions.canLog(pill(on: try day("2026-10-09")), today: today))
        #expect(!WorkCheckPillActions.canLog(pill(on: try day("2026-10-13")), today: today))
    }

    // MARK: - Move All Forward (#49)

    private struct Plan {
        let context: NSManagedObjectContext
        let monday: Date
        let past: CDLessonAssignment
        let upcoming: CDLessonAssignment
        let work: CDWorkModel
        let earlyCheck: CDWorkCheckIn
        let laterCheck: CDWorkCheckIn
        let overdueCheck: CDWorkCheckIn
        let closedWorkCheck: CDWorkCheckIn
    }

    @discardableResult
    private func checkIn(
        for work: CDWorkModel, on date: Date, in context: NSManagedObjectContext
    ) -> CDWorkCheckIn {
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.workID = work.id?.uuidString ?? ""
        checkIn.date = date
        checkIn.status = .scheduled
        checkIn.purpose = "progressCheck"
        return checkIn
    }

    /// Today is Monday 2026-10-12. A lesson left on last Monday, one planned
    /// for Wednesday; open work with checks on Monday and Wednesday (made in
    /// that order) and one left on last Thursday; finished work with a check
    /// still scheduled for Tuesday.
    private func seedPlan() throws -> Plan {
        let context = try CoreDataTestHelpers.makeContext()
        let monday = try day("2026-10-12")
        let past = CDLessonAssignment(context: context)
        past.schedule(for: time(9, on: try day("2026-10-05")), using: AppCalendar.shared)
        let upcoming = CDLessonAssignment(context: context)
        upcoming.schedule(for: time(9, on: try day("2026-10-14")), using: AppCalendar.shared)

        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        work.dueAt = time(13, on: try day("2026-10-14"))
        let earlyCheck = checkIn(for: work, on: time(13, on: monday), in: context)
        let laterCheck = checkIn(for: work, on: time(13, on: try day("2026-10-14")), in: context)

        let stale = CoreDataTestHelpers.seedWorkModel(in: context)
        let overdueCheck = checkIn(for: stale, on: time(13, on: try day("2026-10-08")), in: context)

        let closed = CoreDataTestHelpers.seedWorkModel(in: context)
        closed.status = .mastered
        let closedWorkCheck = checkIn(for: closed, on: time(13, on: try day("2026-10-13")), in: context)
        #expect(CoreDataTestHelpers.save(context))
        return Plan(
            context: context, monday: monday, past: past, upcoming: upcoming, work: work,
            earlyCheck: earlyCheck, laterCheck: laterCheck, overdueCheck: overdueCheck,
            closedWorkCheck: closedWorkCheck
        )
    }

    @Test("Presentations move from today on; open checks move, overdue ones to today; finished work stays")
    func movesOnlyFromTodayOn() throws {
        let plan = try seedPlan()

        let moved = CalendarForwardShiftService.moveForwardOneDay(
            in: plan.context, calendar: AppCalendar.shared, kinds: .everything,
            from: time(8, on: plan.monday), nextSchoolDay: nextWeekday(after:)
        )

        #expect(moved == CalendarForwardShiftService.Result(presentations: 1, checkIns: 3))
        #expect(plan.past.scheduledFor == time(9, on: try day("2026-10-05")))
        #expect(plan.upcoming.scheduledFor == time(9, on: try day("2026-10-15")))
        #expect(plan.overdueCheck.date == time(13, on: plan.monday))
        #expect(plan.closedWorkCheck.date == time(13, on: try day("2026-10-13")))
        #expect(plan.earlyCheck.date == time(13, on: try day("2026-10-13")))
        #expect(plan.laterCheck.date == time(13, on: try day("2026-10-15")))
    }

    @Test("The work's due day is its earliest moved check-in, not the last one processed")
    func dueDayIsTheEarliestCheck() throws {
        let plan = try seedPlan()

        CalendarForwardShiftService.moveForwardOneDay(
            in: plan.context, calendar: AppCalendar.shared, kinds: .everything,
            from: plan.monday, nextSchoolDay: nextWeekday(after:)
        )

        #expect(plan.work.dueAt == time(13, on: try day("2026-10-13")))
    }

    @Test("With the Show filter on Work, presentations stay; work checks move whatever it shows")
    func respectsTheShowFilter() throws {
        let workOnly = try seedPlan()
        let movedWork = CalendarForwardShiftService.moveForwardOneDay(
            in: workOnly.context, calendar: AppCalendar.shared, kinds: .work,
            from: workOnly.monday, nextSchoolDay: nextWeekday(after:)
        )
        #expect(movedWork == CalendarForwardShiftService.Result(presentations: 0, checkIns: 3))
        #expect(workOnly.upcoming.scheduledFor == time(9, on: try day("2026-10-14")))

        let lessonsOnly = try seedPlan()
        let movedLessons = CalendarForwardShiftService.moveForwardOneDay(
            in: lessonsOnly.context, calendar: AppCalendar.shared, kinds: .presentations,
            from: lessonsOnly.monday, nextSchoolDay: nextWeekday(after:)
        )
        #expect(movedLessons == CalendarForwardShiftService.Result(presentations: 1, checkIns: 3))
        #expect(lessonsOnly.earlyCheck.date == time(13, on: try day("2026-10-13")))
    }

    @Test("The confirmation's counts are what the move then moves, and counting moves nothing")
    func pendingCountsMatchTheMove() throws {
        let plan = try seedPlan()

        let pending = CalendarForwardShiftService.pending(
            in: plan.context, calendar: AppCalendar.shared, kinds: .everything, from: plan.monday
        )
        #expect(pending == CalendarForwardShiftService.Result(presentations: 1, checkIns: 3))
        #expect(plan.upcoming.scheduledFor == time(9, on: try day("2026-10-14")))
        #expect(!plan.context.hasChanges)
    }

    @Test("Undo puts every moved day back, the work's due day included")
    func undoPutsItBack() throws {
        let plan = try seedPlan()
        let moved = CalendarForwardShiftService.moveForwardOneDay(
            in: plan.context, calendar: AppCalendar.shared, kinds: .everything,
            from: plan.monday, nextSchoolDay: nextWeekday(after:)
        )
        #expect(CoreDataTestHelpers.save(plan.context))

        let restored = CalendarForwardShiftService.undo(moved.receipt, in: plan.context, calendar: AppCalendar.shared)

        #expect(restored == 4)
        #expect(plan.upcoming.scheduledFor == time(9, on: try day("2026-10-14")))
        #expect(plan.overdueCheck.date == time(13, on: try day("2026-10-08")))
        #expect(plan.earlyCheck.date == time(13, on: plan.monday))
        #expect(plan.laterCheck.date == time(13, on: try day("2026-10-14")))
        #expect(plan.work.dueAt == time(13, on: try day("2026-10-14")))
    }

    @Test("Undo leaves alone a check-in moved again since")
    func undoKeepsLaterEdits() throws {
        let plan = try seedPlan()
        let moved = CalendarForwardShiftService.moveForwardOneDay(
            in: plan.context, calendar: AppCalendar.shared, kinds: .everything,
            from: plan.monday, nextSchoolDay: nextWeekday(after:)
        )
        let draggedTo = time(13, on: try day("2026-10-20"))
        plan.laterCheck.date = draggedTo

        CalendarForwardShiftService.undo(moved.receipt, in: plan.context, calendar: AppCalendar.shared)

        #expect(plan.laterCheck.date == draggedTo)
        #expect(plan.earlyCheck.date == time(13, on: plan.monday))
    }
}
