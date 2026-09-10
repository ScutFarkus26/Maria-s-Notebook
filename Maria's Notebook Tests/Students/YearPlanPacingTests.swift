import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// A year-plan target is a day the guide means to give a lesson, so it can only
/// be a day the school is open.
///
/// The app has always known which days those are, but only some of the paths
/// that wrote a target asked: spacing a sequence counted school days correctly
/// while the first entry, a drag onto a calendar cell, and the MCP tool wrote
/// whatever day they were handed. That is how thirteen children ended up with a
/// lesson targeted at Rosh Hashana.
@Suite("Year Plan — Pacing Around Closed Days")
@MainActor
struct YearPlanPacingTests {

    private func makeContext() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        SchoolCalendarService.shared.invalidateCache()
        return context
    }

    /// A fixed Monday, so no test depends on the day it runs.
    private func day(_ month: Int, _ dayOfMonth: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = month
        comps.day = dayOfMonth
        return AppCalendar.shared.date(from: comps) ?? Date()
    }

    /// Marks a range of days closed, the way the school calendar does.
    private func closeSchool(
        from start: Date, through end: Date, in context: NSManagedObjectContext
    ) {
        var cursor = AppCalendar.startOfDay(start)
        let last = AppCalendar.startOfDay(end)
        while cursor <= last {
            let record = CDNonSchoolDay(context: context)
            record.date = cursor
            cursor = AppCalendar.addingDays(1, to: cursor)
        }
        CoreDataTestHelpers.save(context)
        SchoolCalendarService.shared.invalidateCache()
    }

    @discardableResult
    private func seedEntry(
        in context: NSManagedObjectContext,
        studentID: String,
        lessonID: String = UUID().uuidString,
        plannedDate: Date,
        orderInSequence: Int64,
        spacing: Int64 = 3
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = studentID
        entry.lessonID = lessonID
        entry.plannedDate = plannedDate
        entry.spacingSchoolDays = spacing
        entry.sequenceGroupKey = "Geometry::Polygons"
        entry.orderInSequence = orderInSequence
        entry.statusRaw = YearPlanEntryStatus.planned.rawValue
        return entry
    }

    // MARK: - The Rule

    @Test("a target on a closed day moves forward to the next open one")
    func aClosedDayMovesForward() throws {
        let context = try makeContext()
        // Friday 2026-09-11 is Rosh Hashana; the weekend follows it.
        closeSchool(from: day(9, 11), through: day(9, 11), in: context)

        let landing = YearPlanPacing.schoolDay(onOrAfter: day(9, 11), in: context)
        #expect(landing == day(9, 14))
    }

    @Test("a target already on an open day is left exactly where the guide put it")
    func anOpenDayIsUntouched() throws {
        let context = try makeContext()
        let landing = YearPlanPacing.schoolDay(onOrAfter: day(9, 10), in: context)
        #expect(landing == day(9, 10))
    }

    @Test("a target never moves backwards, even when the open day behind is closer")
    func itNeverMovesBackwards() throws {
        let context = try makeContext()
        // Closed Tuesday through Thursday: Monday is one day back, Friday three forward.
        closeSchool(from: day(9, 15), through: day(9, 17), in: context)

        let landing = YearPlanPacing.schoolDay(onOrAfter: day(9, 15), in: context)
        #expect(landing == day(9, 18))
    }

    // MARK: - A Run Inside A Break

    @Test("a run swallowed by a break cascades from the first open day, not onto it")
    func aRunInsideABreakCascades() throws {
        let context = try makeContext()
        let student = UUID().uuidString
        // A two-week break: 2026-09-21 through 2026-10-04.
        closeSchool(from: day(9, 21), through: day(10, 4), in: context)

        let inBreak = [day(9, 21), day(9, 23), day(9, 28), day(9, 30)].enumerated().map {
            seedEntry(
                in: context, studentID: student, plannedDate: $0.element,
                orderInSequence: Int64($0.offset), spacing: 3
            )
        }
        CoreDataTestHelpers.save(context)

        let moved = YearPlanPacing.resettle(inBreak, in: context)
        #expect(moved == 4)

        // The first lands on the morning school reopens; the rest keep their
        // spacing from it rather than stacking on that same day.
        let dates: [Date] = inBreak.compactMap(\.plannedDate)
        #expect(dates == [day(10, 5), day(10, 8), day(10, 13), day(10, 16)])
        let allDistinct: Bool = Set(dates).count == dates.count
        #expect(allDistinct)
    }

    @Test("entries after the break are carried along only if they would fall out of order")
    func laterEntriesKeepTheirDatesWhenTheyStillFit() throws {
        let context = try makeContext()
        let student = UUID().uuidString
        closeSchool(from: day(9, 21), through: day(10, 4), in: context)

        let inBreak = seedEntry(
            in: context, studentID: student, plannedDate: day(9, 21), orderInSequence: 0, spacing: 3
        )
        // Comfortably after where the moved one lands (2026-10-05).
        let wellAfter = seedEntry(
            in: context, studentID: student, plannedDate: day(10, 20), orderInSequence: 1, spacing: 3
        )
        CoreDataTestHelpers.save(context)

        let moved = YearPlanPacing.resettle([inBreak, wellAfter], in: context)
        #expect(moved == 1)
        #expect(inBreak.plannedDate == day(10, 5))
        #expect(wellAfter.plannedDate == day(10, 20))
    }

    @Test("an entry the cascade would overrun is pushed so the sequence stays in order")
    func laterEntriesArePushedWhenTheyWouldCollide() throws {
        let context = try makeContext()
        let student = UUID().uuidString
        closeSchool(from: day(9, 21), through: day(10, 4), in: context)

        let inBreak = seedEntry(
            in: context, studentID: student, plannedDate: day(9, 21), orderInSequence: 0, spacing: 3
        )
        // Originally before the reopening — it cannot stay there.
        let collides = seedEntry(
            in: context, studentID: student, plannedDate: day(9, 22), orderInSequence: 1, spacing: 2
        )
        CoreDataTestHelpers.save(context)

        YearPlanPacing.resettle([inBreak, collides], in: context)

        #expect(inBreak.plannedDate == day(10, 5))
        // Two school days after 2026-10-05: the 6th, then the 7th.
        #expect(collides.plannedDate == day(10, 7))
    }

    @Test("resettling a plan that needs nothing writes nothing")
    func resettleIsANoOpOnAHealthyPlan() throws {
        let context = try makeContext()
        let student = UUID().uuidString
        let entries = [day(9, 14), day(9, 17), day(9, 18)].enumerated().map {
            seedEntry(
                in: context, studentID: student, plannedDate: $0.element,
                orderInSequence: Int64($0.offset), spacing: 3
            )
        }
        CoreDataTestHelpers.save(context)

        let moved = YearPlanPacing.resettle(entries, in: context)
        #expect(moved == 0)
        #expect(entries.compactMap(\.plannedDate) == [day(9, 14), day(9, 17), day(9, 18)])
    }

    // MARK: - Spacing

    @Test("spacing counts school days, so a break costs the calendar and not the pace")
    func advanceCountsSchoolDays() throws {
        let context = try makeContext()
        closeSchool(from: day(9, 21), through: day(10, 4), in: context)

        // Three school days after Friday 2026-09-18: the break is not counted.
        let landing = YearPlanPacing.advance(from: day(9, 18), bySchoolDays: 3, in: context)
        #expect(landing == day(10, 7))
    }

    @Test("a closed target is recognised, an open one is not")
    func closedDayDetection() throws {
        let context = try makeContext()
        closeSchool(from: day(9, 11), through: day(9, 11), in: context)
        let student = UUID().uuidString
        let onHoliday = seedEntry(
            in: context, studentID: student, plannedDate: day(9, 11), orderInSequence: 0
        )
        let onSchoolDay = seedEntry(
            in: context, studentID: student, plannedDate: day(9, 10), orderInSequence: 1
        )
        CoreDataTestHelpers.save(context)

        #expect(YearPlanPacing.fallsOnClosedDay(onHoliday, in: context))
        #expect(!YearPlanPacing.fallsOnClosedDay(onSchoolDay, in: context))
    }
}
