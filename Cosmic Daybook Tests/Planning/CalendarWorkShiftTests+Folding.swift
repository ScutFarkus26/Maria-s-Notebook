import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Move All Forward never leaves two checks for one work on one day, and never
/// moves a check twice (2026-10-13): a check that would land on a day its work
/// already has one folds into it, and each child's linked copy moves once.
/// Split from CalendarWorkShiftTests.swift for SwiftLint's type-length limit.
extension CalendarWorkShiftTests {

    @Test("Two overdue checks for one work fold into one today, and Undo brings both back")
    func overdueChecksFold() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lastWednesday = day(2026, 6, 3)
        let lastThursday = day(2026, 6, 4)
        let monday = day(2026, 6, 8)
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        work.dueAt = lastWednesday
        let earlier = CDWorkCheckIn.make(for: work, on: time(10, on: lastWednesday), in: context)
        let later = CDWorkCheckIn.make(for: work, on: time(10, on: lastThursday), in: context)
        #expect(CoreDataTestHelpers.save(context))

        let moved = CalendarForwardShiftService.moveForwardOneDay(
            in: context, calendar: AppCalendar.shared, from: monday, nextSchoolDay: nextWeekday(after:)
        )

        #expect(moved.checkIns == 2)
        let scheduledToday = [earlier, later].filter { $0.status == .scheduled && $0.date == time(10, on: monday) }
        #expect(scheduledToday.count == 1)
        #expect([earlier, later].filter { $0.status == .skipped }.count == 1)
        #expect(work.dueAt == time(10, on: monday))

        let restored = CalendarForwardShiftService.undo(moved.receipt, in: context, calendar: AppCalendar.shared)

        #expect(restored == 2)
        #expect(earlier.status == .scheduled && earlier.date == time(10, on: lastWednesday))
        #expect(later.status == .scheduled && later.date == time(10, on: lastThursday))
        #expect(work.dueAt == lastWednesday)
    }

    @Test("An overdue check folds into a check already done on today")
    func overdueFoldsIntoTodaysCompletedCheck() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lastThursday = day(2026, 6, 4)
        let monday = day(2026, 6, 8)
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        let overdue = CDWorkCheckIn.make(for: work, on: time(10, on: lastThursday), in: context)
        let done = CDWorkCheckIn.make(for: work, on: time(9, on: monday), status: .completed, in: context)

        CalendarForwardShiftService.moveForwardOneDay(
            in: context, calendar: AppCalendar.shared, from: monday, nextSchoolDay: nextWeekday(after:)
        )

        #expect(overdue.status == .skipped)
        #expect(overdue.date == time(10, on: lastThursday))
        #expect(done.status == .completed && done.date == time(9, on: monday))
    }

    @Test("Each child's copy moves once, one school day, never two")
    func linkedCopiesMoveOnce() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let monday = day(2026, 6, 8)
        let tuesday = day(2026, 6, 9)
        let wednesday = day(2026, 6, 10)
        let copies = seedLinkedCopies(in: context, count: 3)
        let mondays = copies.map { CDWorkCheckIn.make(for: $0, on: time(10, on: monday), in: context) }
        let tuesdays = copies.map { CDWorkCheckIn.make(for: $0, on: time(10, on: tuesday), in: context) }

        let pending = CalendarForwardShiftService.pending(
            in: context, calendar: AppCalendar.shared, kinds: .everything, from: monday
        )
        let moved = CalendarForwardShiftService.moveForwardOneDay(
            in: context, calendar: AppCalendar.shared, from: monday, nextSchoolDay: nextWeekday(after:)
        )

        #expect(moved.checkIns == 6)
        #expect(pending == moved)
        #expect(moved.receipt.checkIns.count == 6)
        #expect(Set(moved.receipt.checkIns.map(\.objectID)).count == 6)
        #expect(mondays.allSatisfy { $0.status == .scheduled && $0.date == time(10, on: tuesday) })
        #expect(tuesdays.allSatisfy { $0.status == .scheduled && $0.date == time(10, on: wednesday) })
    }

    @Test("A linked copy with a check already on the landing day folds; the others move")
    func linkedCopyClashFolds() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let monday = day(2026, 6, 8)
        let tuesday = day(2026, 6, 9)
        let copies = seedLinkedCopies(in: context, count: 2)
        let first = CDWorkCheckIn.make(for: copies[0], on: time(10, on: monday), in: context)
        let second = CDWorkCheckIn.make(for: copies[1], on: time(10, on: monday), in: context)
        CDWorkCheckIn.make(for: copies[1], on: time(11, on: tuesday), status: .completed, in: context)

        let moved = CalendarForwardShiftService.moveForwardOneDay(
            in: context, calendar: AppCalendar.shared, from: monday, nextSchoolDay: nextWeekday(after:)
        )

        #expect(moved.checkIns == 2)
        #expect(first.date == time(10, on: tuesday))
        #expect(second.status == .skipped)
        #expect(second.date == time(10, on: monday))
    }
}
