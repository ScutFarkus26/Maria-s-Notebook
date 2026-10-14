import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Which open checks are still the plan's (2026-10-14 review): only checks on
/// open work whose child is still in the class. Move All Forward, Clear All,
/// their counts, the strip's pills and its earliest day all read the same set,
/// so a check the strip doesn't show is never moved or counted, and a stale
/// check on closed work never holds the strip months back.
/// Split from CalendarWorkShiftTests.swift for SwiftLint's type-length limit.
extension CalendarWorkShiftTests {

    /// Work for a child who has left, with an open check on `date`.
    private func departedChildsCheck(
        on date: Date, in context: NSManagedObjectContext
    ) throws -> (work: CDWorkModel, checkIn: CDWorkCheckIn) {
        let student = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Ora", lastName: "Levi", enrollmentStatus: .withdrawn
        )
        let work = CoreDataTestHelpers.seedWorkModel(in: context, studentID: try #require(student.id))
        work.dueAt = date
        return (work, CDWorkCheckIn.make(for: work, on: date, in: context))
    }

    @Test("A child who has left keeps her check where it is, and it isn't counted")
    func departedChildsCheckStays() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let monday = day(2026, 6, 8)
        let tuesday = day(2026, 6, 9)
        let enrolled = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane")
        let work = CoreDataTestHelpers.seedWorkModel(in: context, studentID: try #require(enrolled.id))
        let staying = CDWorkCheckIn.make(for: work, on: time(10, on: monday), in: context)
        let departed = try departedChildsCheck(on: time(11, on: monday), in: context)

        let pending = CalendarForwardShiftService.pending(
            in: context, calendar: AppCalendar.shared, kinds: .everything, from: monday
        )
        let moved = CalendarForwardShiftService.moveForwardOneDay(
            in: context, calendar: AppCalendar.shared, from: monday, nextSchoolDay: nextWeekday(after:)
        )

        #expect(pending == moved)
        #expect(moved.checkIns == 1)
        #expect(staying.date == time(10, on: tuesday))
        #expect(departed.checkIn.date == time(11, on: monday))
        #expect(departed.work.dueAt == time(11, on: monday))
        #expect(CalendarForwardShiftService.movableCheckIns(in: context) == [staying])
    }

    @Test("Clear All leaves a departed child's check and closed work's check alone")
    func clearAllLeavesChecksOffThePlan() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let monday = day(2026, 6, 8)
        let departed = try departedChildsCheck(on: time(11, on: monday), in: context)
        let closed = CoreDataTestHelpers.seedWorkModel(in: context)
        closed.status = .done
        let closedCheck = CDWorkCheckIn.make(for: closed, on: time(12, on: monday), in: context)

        let cleared = CalendarClearAllService.clearAll(in: context)

        #expect(cleared.isEmpty)
        #expect(!departed.checkIn.isDeleted && departed.checkIn.status == .scheduled)
        #expect(!closedCheck.isDeleted && closedCheck.status == .scheduled)
    }

    @Test("The strip's earliest day ignores a stale check on closed work and a departed child's check")
    func earliestCheckIsOnThePlan() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let march = day(2026, 3, 2)
        let april = day(2026, 4, 6)
        let monday = day(2026, 6, 8)
        let closed = CoreDataTestHelpers.seedWorkModel(in: context)
        closed.status = .mastered
        CDWorkCheckIn.make(for: closed, on: time(9, on: march), in: context)
        _ = try departedChildsCheck(on: time(9, on: april), in: context)
        let open = CoreDataTestHelpers.seedWorkModel(in: context)
        CDWorkCheckIn.make(for: open, on: time(13, on: monday), in: context)

        #expect(CalendarForwardShiftService.firstScheduledCheckInDate(in: context) == time(13, on: monday))
        #expect(WeekPlanDayWindow.earliestDay(
            today: monday,
            firstPresentation: nil,
            firstCheckIn: CalendarForwardShiftService.firstScheduledCheckInDate(in: context),
            calendar: AppCalendar.shared
        ) == monday)
    }

    @Test("The strip's pills are the same set: open work, child still in class")
    func stripShowsOnlyThePlan() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let monday = day(2026, 6, 8)
        let open = CoreDataTestHelpers.seedWorkModel(in: context)
        let shown = CDWorkCheckIn.make(for: open, on: time(10, on: monday), in: context)
        let departed = try departedChildsCheck(on: time(11, on: monday), in: context)
        let closed = CoreDataTestHelpers.seedWorkModel(in: context)
        closed.status = .done
        let closedCheck = CDWorkCheckIn.make(for: closed, on: time(12, on: monday), in: context)

        let onPlan = CalendarForwardShiftService.onPlan([shown, departed.checkIn, closedCheck], in: context)

        #expect(onPlan == [shown])
    }
}
